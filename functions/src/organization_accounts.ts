import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as functions from 'firebase-functions';
import * as nodemailer from 'nodemailer';

import {COL} from './firestore_paths';
import {
  buildUserSearchTokens,
  matchesUserSearch,
  normalizeUserSearchText,
  userSearchRelevance,
} from './user_search_index';

const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const INVITE_MAX_FAILED_ATTEMPTS = 8;
const EMAIL_RESEND_COOLDOWN_MS = 60 * 1000;
const ORGANIZATION_SCHEMA_VERSION = 1;
const ALLOWED_PROVIDERS = new Set([
  'google.com',
  'apple.com',
  'password',
]);
const MANAGER_ROLES = new Set(['owner', 'manager', 'editor']);
const ALL_ROLES = new Set(['owner', 'manager', 'editor', 'viewer']);
const VERIFICATION_STATUSES = new Set([
  'unverified',
  'pending',
  'verified',
  'rejected',
]);
const PARTNER_STATUSES = new Set(['none', 'partner']);
const ENTITLEMENT_STATUSES = new Set(['inactive', 'active', 'suspended']);
const RESERVED_HANDLES = new Set([
  'admin',
  'administrator',
  'support',
  'wefilling',
  'system',
  'anonymous',
]);

type OrganizationRole = 'owner' | 'manager' | 'editor' | 'viewer';

export type OrganizationProvisionInput = {
  requestId: string;
  name: string;
  handle: string;
  organizationType: string;
  affiliation: string;
  description: string;
  logoUrl: string;
  contactEmail: string;
  ownerContactEmail: string;
  allowedLoginProviders: string[];
  targetEnvironment: string;
};

export type OrganizationProvisionResult = {
  organizationId: string;
  inviteId: string;
  invitationToken: string;
  lifecycleStatus: string;
  provisioningStatus: string;
  reused: boolean;
};

function db(): admin.firestore.Firestore {
  return admin.firestore();
}

async function requirePlatformAdminUid(operatorUid: unknown): Promise<string> {
  const uid = requireString(operatorUid, 'operatorUid', 128);
  const operator = await admin.auth().getUser(uid);
  if (operator.customClaims?.platformAdmin !== true) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'platformAdmin access is required.',
    );
  }
  return uid;
}

function asString(value: unknown, maxLength = 500): string {
  return String(value ?? '').trim().normalize('NFC').slice(0, maxLength);
}

function requireString(
  value: unknown,
  field: string,
  maxLength = 500,
): string {
  const normalized = asString(value, maxLength);
  if (!normalized) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `${field} is required.`,
    );
  }
  return normalized;
}

function normalizeEmail(value: unknown): string {
  const email = asString(value, 320).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'A valid contact email is required.',
    );
  }
  return email;
}

function normalizePublicUrl(
  value: unknown,
  field: string,
  maxLength = 2000,
): string {
  const normalized = asString(value, maxLength);
  if (!normalized) return '';
  try {
    const parsed = new URL(normalized);
    if (!['https:', 'http:'].includes(parsed.protocol) ||
        parsed.username || parsed.password) throw new Error('unsafe URL');
  } catch (_) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `${field} must be a valid public HTTP(S) URL.`,
    );
  }
  return normalized;
}

export function normalizeOrganizationHandle(value: unknown): string {
  const handle = asString(value, 40)
    .replace(/^@+/, '')
    .toLowerCase();
  if (handle.length < 2 || handle.length > 30 ||
      !/^[a-z][a-z0-9_]*$/.test(handle) ||
      RESERVED_HANDLES.has(handle)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'The organization ID must be 2–30 lowercase letters, numbers, or underscores and start with a letter.',
    );
  }
  return handle;
}

function normalizeProviders(value: unknown): string[] {
  if (!Array.isArray(value)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'At least one login provider is required.',
    );
  }
  const providers = Array.from(new Set(
    value.map((item) => asString(item, 40)).filter(Boolean),
  ));
  if (providers.length === 0 ||
      providers.some((provider) => !ALLOWED_PROVIDERS.has(provider))) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Supported providers are google.com, apple.com, and password.',
    );
  }
  return providers.sort();
}

function normalizedProvisionInput(
  input: OrganizationProvisionInput,
): OrganizationProvisionInput {
  return {
    requestId: requireString(input.requestId, 'REQUEST_ID', 120),
    name: requireString(input.name, 'ORG_NAME', 100),
    handle: normalizeOrganizationHandle(input.handle),
    organizationType: requireString(input.organizationType, 'ORG_TYPE', 80),
    affiliation: asString(input.affiliation, 160),
    description: asString(input.description, 2000),
    logoUrl: normalizePublicUrl(input.logoUrl, 'ORG_LOGO'),
    contactEmail: normalizeEmail(input.contactEmail),
    ownerContactEmail: normalizeEmail(input.ownerContactEmail),
    allowedLoginProviders: normalizeProviders(input.allowedLoginProviders),
    targetEnvironment: requireString(
      input.targetEnvironment,
      'TARGET_ENVIRONMENT',
      40,
    ),
  };
}

function stableHash(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function requestDocumentId(environment: string, requestId: string): string {
  return `org_request_${stableHash(`${environment}:${requestId}`).slice(0, 40)}`;
}

function organizationIdForRequest(
  environment: string,
  requestId: string,
): string {
  return `org_${stableHash(`${environment}:${requestId}:organization`).slice(0, 28)}`;
}

function newInvitationToken(): string {
  return crypto.randomBytes(32).toString('base64url');
}

function invitationIdentity(token: string): {hash: string; id: string} {
  if (!/^[A-Za-z0-9_-]{40,180}$/.test(token)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'The organization invitation is invalid.',
    );
  }
  const hash = stableHash(token);
  return {hash, id: `inv_${hash.slice(0, 48)}`};
}

function publicOrganizationData(
  input: OrganizationProvisionInput,
  operatorUid: string,
): Record<string, unknown> {
  return {
    schemaVersion: ORGANIZATION_SCHEMA_VERSION,
    name: input.name,
    handle: input.handle,
    organizationType: input.organizationType,
    affiliation: input.affiliation,
    activityArea: '',
    logoUrl: input.logoUrl,
    coverImageUrl: '',
    shortDescription: input.description.slice(0, 160),
    description: input.description,
    supportedLanguages: [],
    publicContact: input.contactEmail,
    websiteUrl: '',
    verificationStatus: 'unverified',
    partnerStatus: 'none',
    lifecycleStatus: 'awaiting_owner',
    isSearchable: false,
    createdByUid: operatorUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    publishedAt: null,
  };
}

function organizationSearchTokens(name: string, handle: string): string[] {
  return Array.from(new Set([
    ...buildUserSearchTokens(name),
    ...buildUserSearchTokens(handle),
    ...buildUserSearchTokens(`@${handle}`),
  ])).sort();
}

function inviteDocument(
  organizationId: string,
  operatorUid: string,
  recipientEmail: string,
  providers: string[],
  tokenHash: string,
  provisioningId: string,
): Record<string, unknown> {
  return {
    organizationId,
    recipientContactEmail: recipientEmail,
    allowedLoginProviders: providers,
    role: 'owner',
    status: 'pending',
    tokenHash,
    expiresAt: admin.firestore.Timestamp.fromMillis(
      Date.now() + INVITE_TTL_MS,
    ),
    createdByUid: operatorUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    acceptedByUid: null,
    acceptedAt: null,
    attemptCount: 0,
    provisioningId,
  };
}

function dataFingerprint(input: OrganizationProvisionInput): string {
  return stableHash(JSON.stringify({
    ...input,
    allowedLoginProviders: [...input.allowedLoginProviders].sort(),
  }));
}

/**
 * Admin-SDK-only primitive used by the operator CLI. It is intentionally not
 * exported as a callable Cloud Function.
 */
export async function provisionOrganizationForAdmin(
  rawInput: OrganizationProvisionInput,
  operatorUid: string,
): Promise<OrganizationProvisionResult> {
  const input = normalizedProvisionInput(rawInput);
  const normalizedOperatorUid = await requirePlatformAdminUid(operatorUid);
  const provisioningId = requestDocumentId(
    input.targetEnvironment,
    input.requestId,
  );
  const organizationId = organizationIdForRequest(
    input.targetEnvironment,
    input.requestId,
  );
  const token = newInvitationToken();
  const inviteIdentity = invitationIdentity(token);
  const fingerprint = dataFingerprint(input);
  const store = db();
  const provisioningRef = store
    .collection(COL.organizationProvisioning)
    .doc(provisioningId);
  const organizationRef = store
    .collection(COL.organizations)
    .doc(organizationId);
  const privateRef = store
    .collection(COL.organizationPrivate)
    .doc(organizationId);
  const entitlementRef = store
    .collection(COL.organizationEntitlements)
    .doc(organizationId);
  const handleRef = store.collection(COL.identityHandles).doc(input.handle);
  const legacyNicknameRef = store
    .collection(COL.nicknameClaims)
    .doc(input.handle);
  const inviteRef = store
    .collection(COL.organizationInvites)
    .doc(inviteIdentity.id);
  const auditRef = store.collection(COL.organizationAuditLogs).doc();

  const result = await store.runTransaction(async (transaction) => {
    const [provisioning, handle, legacyNickname] = await Promise.all([
      transaction.get(provisioningRef),
      transaction.get(handleRef),
      transaction.get(legacyNicknameRef),
    ]);
    if (provisioning.exists) {
      if (provisioning.get('requestFingerprint') !== fingerprint) {
        throw new functions.https.HttpsError(
          'already-exists',
          'REQUEST_ID was already used with different organization data.',
        );
      }
      return {
        organizationId: String(provisioning.get('organizationId') ?? ''),
        inviteId: String(provisioning.get('inviteId') ?? ''),
        lifecycleStatus: String(
          provisioning.get('lifecycleStatus') ?? 'awaiting_owner',
        ),
        provisioningStatus: String(provisioning.get('status') ?? ''),
        reused: true,
      };
    }
    if (handle.exists || legacyNickname.exists) {
      throw new functions.https.HttpsError(
        'already-exists',
        'The organization ID is already reserved.',
      );
    }

    transaction.create(organizationRef, publicOrganizationData(
      input,
      normalizedOperatorUid,
    ));
    transaction.create(privateRef, {
      schemaVersion: ORGANIZATION_SCHEMA_VERSION,
      contactEmail: input.contactEmail,
      ownerContactEmail: input.ownerContactEmail,
      contract: {},
      payment: {},
      verificationDocuments: [],
      internalNotes: '',
      suspensionReason: '',
      ownershipHistory: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.create(entitlementRef, {
      organizationId,
      status: 'inactive',
      features: {},
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.create(handleRef, {
      normalizedHandle: input.handle,
      entityType: 'organization',
      entityId: organizationId,
      status: 'claimed',
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.create(inviteRef, inviteDocument(
      organizationId,
      normalizedOperatorUid,
      input.ownerContactEmail,
      input.allowedLoginProviders,
      inviteIdentity.hash,
      provisioningId,
    ));
    transaction.create(provisioningRef, {
      requestId: input.requestId,
      requestFingerprint: fingerprint,
      targetEnvironment: input.targetEnvironment,
      organizationId,
      inviteId: inviteIdentity.id,
      handle: input.handle,
      status: 'invitation_created',
      lifecycleStatus: 'awaiting_owner',
      requestedByUid: normalizedOperatorUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    transaction.create(auditRef, {
      organizationId,
      action: 'organization_provisioned',
      actorUid: normalizedOperatorUid,
      targetUid: null,
      requestId: input.requestId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      organizationId,
      inviteId: inviteIdentity.id,
      lifecycleStatus: 'awaiting_owner',
      provisioningStatus: 'invitation_created',
      reused: false,
    };
  });

  if (result.reused) {
    // An invitation token is deliberately non-recoverable. Reusing a request
    // never emits a different token for the already-created invite.
    return {...result, invitationToken: ''};
  }
  return {...result, invitationToken: token};
}

function timestampMillis(value: unknown): number | null {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return null;
}

function validatePendingInvite(
  snapshot: admin.firestore.DocumentSnapshot,
  expectedHash: string,
): Record<string, unknown> {
  const value = snapshot.data() as Record<string, unknown> | undefined;
  const expiresAt = timestampMillis(value?.expiresAt);
  if (!snapshot.exists || !value || value.tokenHash !== expectedHash ||
      value.status !== 'pending' || !expiresAt || expiresAt <= Date.now() ||
      Number(value.attemptCount ?? 0) >= INVITE_MAX_FAILED_ATTEMPTS) {
    throw new functions.https.HttpsError(
      'not-found',
      'This organization invitation is invalid or expired.',
    );
  }
  return value;
}

export const previewOrganizationInvite = functions
  .runWith({timeoutSeconds: 15, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (raw) => {
    const identity = invitationIdentity(asString(raw?.token, 180));
    const invite = await db().collection(COL.organizationInvites)
      .doc(identity.id)
      .get();
    const inviteData = validatePendingInvite(invite, identity.hash);
    const organizationId = asString(inviteData.organizationId, 128);
    const organization = await db().collection(COL.organizations)
      .doc(organizationId)
      .get();
    if (!organization.exists ||
        !['awaiting_owner', 'active'].includes(
          asString(organization.get('lifecycleStatus'), 40),
        )) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'This organization invitation is not currently available.',
      );
    }
    return {
      valid: true,
      organization: {
        id: organization.id,
        name: asString(organization.get('name'), 100),
        handle: asString(organization.get('handle'), 40),
        organizationType: asString(
          organization.get('organizationType'),
          80,
        ),
        affiliation: asString(organization.get('affiliation'), 160),
        activityArea: asString(organization.get('activityArea'), 160),
        logoUrl: asString(organization.get('logoUrl'), 2000),
        coverImageUrl: asString(organization.get('coverImageUrl'), 2000),
        shortDescription: asString(
          organization.get('shortDescription'),
          300,
        ),
        description: asString(organization.get('description'), 2000),
        publicContact: asString(organization.get('publicContact'), 320),
        websiteUrl: asString(organization.get('websiteUrl'), 2000),
      },
      role: asString(inviteData.role, 30),
      allowedLoginProviders: normalizeProviders(
        inviteData.allowedLoginProviders,
      ),
      expiresAtMillis: timestampMillis(inviteData.expiresAt),
    };
  });

function currentSignInProvider(context: functions.https.CallableContext): string {
  const firebase = context.auth?.token.firebase;
  if (!firebase || typeof firebase !== 'object') return '';
  return asString(
    (firebase as Record<string, unknown>).sign_in_provider,
    40,
  );
}

function completedPersonalProfile(data: Record<string, unknown>): boolean {
  const registration = asString(data.registrationStatus, 40);
  return registration === 'complete' ||
    (registration === '' && data.emailVerified === true &&
      asString(data.nickname, 100).length > 0);
}

function membershipId(organizationId: string, uid: string): string {
  return `${organizationId}_${uid}`;
}

type InviteAcceptanceDecision = {
  status: 'completed' | 'identity_pending_review' | 'consent_required';
  organizationId: string;
  organizationName: string;
  accountUsage?: string;
};

type InviteAcceptanceTransactionDecision = InviteAcceptanceDecision | {
  status: 'provider_not_allowed' | 'email_mismatch';
  organizationId: string;
  organizationName: string;
};

export const acceptOrganizationInvite = functions
  .runWith({timeoutSeconds: 30, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (raw, context): Promise<InviteAcceptanceDecision> => {
    const uid = asString(context.auth?.uid, 128);
    if (!uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Sign in with an allowed provider to accept this invitation.',
      );
    }
    const identity = invitationIdentity(asString(raw?.token, 180));
    const signInProvider = currentSignInProvider(context);
    const linkExistingPersonalProfile =
      raw?.linkExistingPersonalProfile === true;
    const store = db();
    const authUser = await admin.auth().getUser(uid);
    const inviteRef = store.collection(COL.organizationInvites)
      .doc(identity.id);
    const inviteBefore = await inviteRef.get();
    const preliminaryRaw = inviteBefore.data() as
      Record<string, unknown> | undefined;
    if (!inviteBefore.exists || !preliminaryRaw ||
        preliminaryRaw.tokenHash !== identity.hash) {
      throw new functions.https.HttpsError(
        'not-found',
        'This organization invitation is invalid or expired.',
      );
    }
    const alreadyAcceptedByCurrentUser =
      preliminaryRaw.status === 'accepted' &&
      preliminaryRaw.acceptedByUid === uid;
    const preliminary = alreadyAcceptedByCurrentUser ?
      preliminaryRaw : validatePendingInvite(inviteBefore, identity.hash);
    const organizationId = requireString(
      preliminary.organizationId,
      'organizationId',
      128,
    );
    const organizationRef = store.collection(COL.organizations)
      .doc(organizationId);
    const userRef = store.collection(COL.users).doc(uid);
    const membershipRef = store.collection(COL.organizationMemberships)
      .doc(membershipId(organizationId, uid));
    const searchRef = store.collection(COL.searchEntities)
      .doc(`organization_${organizationId}`);
    const provisioningId = asString(preliminary.provisioningId, 128);
    const provisioningRef = store.collection(COL.organizationProvisioning)
      .doc(provisioningId);
    const auditRef = store.collection(COL.organizationAuditLogs).doc();

    const decision = await store.runTransaction<
      InviteAcceptanceTransactionDecision
    >(async (transaction) => {
      const [invite, organization, user, existingMembership] =
        await Promise.all([
          transaction.get(inviteRef),
          transaction.get(organizationRef),
          transaction.get(userRef),
          transaction.get(membershipRef),
        ]);
      if (existingMembership.exists &&
          existingMembership.get('status') === 'active') {
        return {
          status: 'completed' as const,
          organizationId,
          organizationName: asString(organization.get('name'), 100),
          accountUsage: asString(user.get('accountUsage'), 40) || 'personal',
        };
      }
      const inviteData = validatePendingInvite(invite, identity.hash);
      const organizationName = asString(organization.get('name'), 100);
      const previousLifecycle = asString(
        organization.get('lifecycleStatus'),
        40,
      );
      if (!organization.exists ||
          !['awaiting_owner', 'active'].includes(previousLifecycle)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The organization is not awaiting an owner.',
        );
      }
      const providers = normalizeProviders(
        inviteData.allowedLoginProviders,
      );
      if (!providers.includes(signInProvider)) {
        const attempts = Number(inviteData.attemptCount ?? 0) + 1;
        transaction.update(inviteRef, {
          attemptCount: attempts,
          ...(attempts >= INVITE_MAX_FAILED_ATTEMPTS ?
            {status: 'locked'} : {}),
          lastFailedAttemptAt:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          status: 'provider_not_allowed' as const,
          organizationId,
          organizationName,
        };
      }
      const recipientEmail = normalizeEmail(
        inviteData.recipientContactEmail,
      );
      const authEmail = asString(authUser.email, 320).toLowerCase();
      const emailMatches = authEmail === recipientEmail;
      const reviewApproved =
        inviteData.identityReviewApprovedForUid === uid;
      const providerAllowsReviewedEmailMismatch =
        signInProvider === 'apple.com' || signInProvider === 'google.com';
      if (providerAllowsReviewedEmailMismatch && !emailMatches &&
          !reviewApproved) {
        transaction.update(inviteRef, {
          identityReviewStatus: 'required',
          identityReviewRequestedByUid: uid,
          identityReviewProvider: signInProvider,
          identityReviewRequestedAt:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        if (provisioningId) {
          transaction.set(provisioningRef, {
            status: 'identity_pending_review',
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});
        }
        return {
          status: 'identity_pending_review' as const,
          organizationId,
          organizationName,
        };
      }
      // Password invitations must always use the exact invited email. Google
      // may use a different verified address only after the operator approves
      // this exact Firebase UID. Apple can omit or relay the email after first
      // sign-in, so its UID/provider review is authoritative.
      const exactEmailRequired = signInProvider === 'password';
      const verifiedProviderEmailRequired = signInProvider === 'google.com';
      if ((exactEmailRequired && (!authUser.emailVerified || !emailMatches)) ||
          (verifiedProviderEmailRequired && !authUser.emailVerified)) {
        const attempts = Number(inviteData.attemptCount ?? 0) + 1;
        transaction.update(inviteRef, {
          attemptCount: attempts,
          ...(attempts >= INVITE_MAX_FAILED_ATTEMPTS ?
            {status: 'locked'} : {}),
          lastFailedAttemptAt:
            admin.firestore.FieldValue.serverTimestamp(),
        });
        return {
          status: 'email_mismatch' as const,
          organizationId,
          organizationName,
        };
      }

      const userData = (user.data() ?? {}) as Record<string, unknown>;
      const personal = user.exists && completedPersonalProfile(userData);
      const organizationOnly = user.exists &&
        userData.accountUsage === 'organization_only' &&
        userData.provisioningSource === 'platform_admin_invite';
      if (personal && !linkExistingPersonalProfile) {
        return {
          status: 'consent_required' as const,
          organizationId,
          organizationName,
          accountUsage: 'personal',
        };
      }
      if (user.exists && !personal && !organizationOnly) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'This login is linked to an unfinished personal account. Administrator review is required.',
        );
      }

      const roleValue = asString(inviteData.role, 30);
      const role = (ALL_ROLES.has(roleValue) ? roleValue : 'owner') as
        OrganizationRole;
      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.create(membershipRef, {
        organizationId,
        uid,
        role,
        status: 'active',
        createdByUid: asString(inviteData.createdByUid, 128),
        inviteId: invite.id,
        createdAt: now,
        updatedAt: now,
      });
      if (!user.exists) {
        transaction.create(userRef, {
          uid,
          accountUsage: 'organization_only',
          publicPersonalProfileEnabled: false,
          provisioningSource: 'platform_admin_invite',
          registrationStatus: 'organization_only',
          signupProvider: signInProvider,
          searchable: false,
          nicknameSearchTokens: [],
          createdAt: now,
          updatedAt: now,
        });
      }
      transaction.update(inviteRef, {
        status: 'accepted',
        acceptedByUid: uid,
        acceptedAt: now,
        identityReviewStatus: reviewApproved ? 'approved' : 'not_required',
      });
      transaction.update(organizationRef, {
        lifecycleStatus: 'active',
        isSearchable: true,
        updatedAt: now,
        ...(previousLifecycle === 'awaiting_owner' ? {publishedAt: now} : {}),
      });
      transaction.set(searchRef, {
        entityType: 'organization',
        entityId: organizationId,
        name: organizationName,
        handle: asString(organization.get('handle'), 40),
        organizationType: asString(
          organization.get('organizationType'),
          80,
        ),
        affiliation: asString(organization.get('affiliation'), 160),
        logoUrl: asString(organization.get('logoUrl'), 2000),
        verificationStatus: asString(
          organization.get('verificationStatus'),
          40,
        ),
        partnerStatus: asString(organization.get('partnerStatus'), 40),
        searchTokens: organizationSearchTokens(
          organizationName,
          asString(organization.get('handle'), 40),
        ),
        isSearchable: true,
        updatedAt: now,
      }, {merge: true});
      if (provisioningId) {
        transaction.set(provisioningRef, {
          status: 'completed',
          lifecycleStatus: 'active',
          ownerUid: uid,
          updatedAt: now,
          completedAt: now,
        }, {merge: true});
      }
      transaction.create(auditRef, {
        organizationId,
        action: 'organization_invite_accepted',
        actorUid: uid,
        targetUid: uid,
        inviteId: invite.id,
        createdAt: now,
      });
      return {
        status: 'completed' as const,
        organizationId,
        organizationName,
        accountUsage: personal ? 'personal' : 'organization_only',
      };
    });
    if (decision.status === 'provider_not_allowed') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Use one of the login methods allowed by this invitation.',
      );
    }
    if (decision.status === 'email_mismatch') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'The verified login email does not match this invitation.',
      );
    }
    // The two transaction-only failure states are converted to HttpsError
    // above, so callers can only receive one of the public success/review
    // decisions declared by the callable contract.
    return decision as InviteAcceptanceDecision;
  });

function configuredMailTransport(): nodemailer.Transporter | null {
  const config = functions.config().gmail ?? {};
  const user = asString(config.user || process.env.GMAIL_USER, 320);
  const password = asString(
    config.password || process.env.GMAIL_PASSWORD,
    300,
  ).replace(/\s+/g, '');
  if (!user || !password || password === '여기에16자리앱비밀번호입력') {
    return null;
  }
  return nodemailer.createTransport({
    host: 'smtp.gmail.com',
    port: 465,
    secure: true,
    auth: {user, pass: password},
  });
}

export const prepareOrganizationPasswordInvite = functions
  .runWith({timeoutSeconds: 30, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (raw) => {
    const token = asString(raw?.token, 180);
    const identity = invitationIdentity(token);
    const store = db();
    const inviteRef = store.collection(COL.organizationInvites)
      .doc(identity.id);
    const invite = await inviteRef.get();
    const data = validatePendingInvite(invite, identity.hash);
    const providers = normalizeProviders(data.allowedLoginProviders);
    if (!providers.includes('password')) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Email login is not enabled for this invitation.',
      );
    }
    const previousSentAt = timestampMillis(data.passwordSetupSentAt);
    if (previousSentAt &&
        Date.now() - previousSentAt < EMAIL_RESEND_COOLDOWN_MS) {
      throw new functions.https.HttpsError(
        'resource-exhausted',
        'Please wait before requesting another email.',
      );
    }
    const email = normalizeEmail(data.recipientContactEmail);
    let authUser: admin.auth.UserRecord;
    try {
      authUser = await admin.auth().getUserByEmail(email);
    } catch (error) {
      if ((error as {code?: string}).code !== 'auth/user-not-found') {
        throw error;
      }
      try {
        authUser = await admin.auth().createUser({
          email,
          emailVerified: false,
        });
      } catch (createError) {
        // Two setup taps may both observe a missing account. The Auth email
        // uniqueness constraint is authoritative; the loser resumes with the
        // account created by the winner instead of surfacing a false failure.
        if ((createError as {code?: string}).code !==
            'auth/email-already-exists') {
          throw createError;
        }
        authUser = await admin.auth().getUserByEmail(email);
      }
    }
    const providerIds = authUser.providerData.map(
      (provider) => provider.providerId,
    );
    if (providerIds.length > 0 && !providerIds.includes('password')) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'This email already uses another login provider.',
      );
    }
    const actionLink = await admin.auth().generatePasswordResetLink(email, {
      url: 'https://wefilling.app/organization-invite',
      handleCodeInApp: false,
    });
    const verificationLink = authUser.emailVerified ? '' :
      await admin.auth().generateEmailVerificationLink(email, {
        url: 'https://wefilling.app/organization-invite',
        handleCodeInApp: false,
      });
    const transporter = configuredMailTransport();
    if (!transporter) {
      throw new functions.https.HttpsError(
        'unavailable',
        'Organization invitation email delivery is not configured.',
      );
    }
    const organization = await store.collection(COL.organizations)
      .doc(asString(data.organizationId, 128))
      .get();
    const organizationName = asString(organization.get('name'), 100);
    const fromAddress = asString(
      functions.config().gmail?.user || process.env.GMAIL_USER,
      320,
    );
    await transporter.sendMail({
      from: `Wefilling <${fromAddress}>`,
      to: email,
      subject: `[Wefilling] ${organizationName} account setup`,
      text: [
        `${organizationName} organization account setup`,
        '',
        'Set a password using the secure Firebase link below:',
        actionLink,
        ...(verificationLink ? [
          '',
          'Verify ownership of the invited email using this link:',
          verificationLink,
        ] : []),
        '',
        'After setting the password, return to the original private invitation and sign in.',
      ].join('\n'),
    });
    await inviteRef.update({
      preparedAuthUid: authUser.uid,
      passwordSetupSentAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {emailSent: true};
  });

export const getMyOrganizationAccess = functions
  .runWith({timeoutSeconds: 20, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (_raw, context) => {
    const uid = asString(context.auth?.uid, 128);
    if (!uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Sign in is required.',
      );
    }
    const memberships = await db().collection(COL.organizationMemberships)
      .where('uid', '==', uid)
      .get();
    const active = memberships.docs.filter(
      (document) => document.get('status') === 'active',
    );
    const organizations = active.length === 0 ? [] : await db().getAll(
      ...active.map((membership) => db().collection(COL.organizations)
        .doc(asString(membership.get('organizationId'), 128))),
    );
    const result = active.map((membership, index) => {
      const organization = organizations[index];
      const lifecycleStatus = asString(
        organization?.get('lifecycleStatus'),
        40,
      );
      return {
        membershipId: membership.id,
        organizationId: asString(membership.get('organizationId'), 128),
        role: asString(membership.get('role'), 30),
        membershipStatus: 'active',
        lifecycleStatus,
        organization: organization?.exists ? {
          id: organization.id,
          name: asString(organization.get('name'), 100),
          handle: asString(organization.get('handle'), 40),
          logoUrl: asString(organization.get('logoUrl'), 2000),
          coverImageUrl: asString(organization.get('coverImageUrl'), 2000),
          organizationType: asString(
            organization.get('organizationType'),
            80,
          ),
          affiliation: asString(organization.get('affiliation'), 160),
          activityArea: asString(organization.get('activityArea'), 160),
          shortDescription: asString(
            organization.get('shortDescription'),
            300,
          ),
          description: asString(organization.get('description'), 2000),
          publicContact: asString(organization.get('publicContact'), 320),
          websiteUrl: asString(organization.get('websiteUrl'), 2000),
          verificationStatus: asString(
            organization.get('verificationStatus'),
            40,
          ),
          partnerStatus: asString(organization.get('partnerStatus'), 40),
        } : null,
      };
    });
    return {organizations: result};
  });

function editableOrganizationFields(raw: unknown): Record<string, unknown> {
  const source = raw && typeof raw === 'object' ?
    raw as Record<string, unknown> : {};
  const result: Record<string, unknown> = {};
  const stringFields: Array<[string, number]> = [
    ['name', 100],
    ['organizationType', 80],
    ['affiliation', 160],
    ['activityArea', 160],
    ['logoUrl', 2000],
    ['coverImageUrl', 2000],
    ['shortDescription', 300],
    ['description', 2000],
    ['publicContact', 320],
    ['websiteUrl', 2000],
  ];
  for (const [field, maxLength] of stringFields) {
    if (Object.prototype.hasOwnProperty.call(source, field)) {
      const value = asString(source[field], maxLength);
      if (['name', 'organizationType'].includes(field) && !value) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `${field} cannot be empty.`,
        );
      }
      result[field] = ['logoUrl', 'coverImageUrl', 'websiteUrl']
        .includes(field) ?
        normalizePublicUrl(value, field, maxLength) : value;
    }
  }
  if (Object.prototype.hasOwnProperty.call(source, 'supportedLanguages')) {
    const languages = Array.isArray(source.supportedLanguages) ?
      source.supportedLanguages : [];
    result.supportedLanguages = Array.from(new Set(languages
      .map((value) => asString(value, 20))
      .filter(Boolean))).slice(0, 10);
  }
  if (Object.keys(result).length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'No editable organization profile fields were provided.',
    );
  }
  return result;
}

export const updateMyOrganizationProfile = functions
  .runWith({timeoutSeconds: 20, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (raw, context) => {
    const uid = asString(context.auth?.uid, 128);
    const organizationId = asString(raw?.organizationId, 128);
    if (!uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Sign in is required.',
      );
    }
    if (!organizationId || organizationId.includes('/')) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A valid organization ID is required.',
      );
    }
    const update = editableOrganizationFields(raw?.profile);
    const store = db();
    const membershipRef = store.collection(COL.organizationMemberships)
      .doc(membershipId(organizationId, uid));
    const organizationRef = store.collection(COL.organizations)
      .doc(organizationId);
    const searchRef = store.collection(COL.searchEntities)
      .doc(`organization_${organizationId}`);
    await store.runTransaction(async (transaction) => {
      const [membership, organization] = await Promise.all([
        transaction.get(membershipRef),
        transaction.get(organizationRef),
      ]);
      const role = asString(membership.get('role'), 30);
      if (!membership.exists || membership.get('status') !== 'active' ||
          !MANAGER_ROLES.has(role)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Organization editor access is required.',
        );
      }
      if (!organization.exists ||
          organization.get('lifecycleStatus') !== 'active') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The organization is not active.',
        );
      }
      const mergedName = asString(update.name ?? organization.get('name'), 100);
      const handle = asString(organization.get('handle'), 40);
      const now = admin.firestore.FieldValue.serverTimestamp();
      transaction.update(organizationRef, {
        ...update,
        updatedAt: now,
      });
      transaction.set(searchRef, {
        name: mergedName,
        organizationType: asString(
          update.organizationType ?? organization.get('organizationType'),
          80,
        ),
        affiliation: asString(
          update.affiliation ?? organization.get('affiliation'),
          160,
        ),
        logoUrl: asString(update.logoUrl ?? organization.get('logoUrl'), 2000),
        coverImageUrl: asString(
          update.coverImageUrl ?? organization.get('coverImageUrl'),
          2000,
        ),
        activityArea: asString(
          update.activityArea ?? organization.get('activityArea'),
          160,
        ),
        shortDescription: asString(
          update.shortDescription ?? organization.get('shortDescription'),
          300,
        ),
        description: asString(
          update.description ?? organization.get('description'),
          2000,
        ),
        publicContact: asString(
          update.publicContact ?? organization.get('publicContact'),
          320,
        ),
        websiteUrl: asString(
          update.websiteUrl ?? organization.get('websiteUrl'),
          2000,
        ),
        searchTokens: organizationSearchTokens(mergedName, handle),
        updatedAt: now,
      }, {merge: true});
    });
    return {success: true};
  });

export const searchOrganizationsSecure = functions
  .runWith({timeoutSeconds: 20, memory: '256MB', enforceAppCheck: true})
  .https.onCall(async (raw, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Sign in is required.',
      );
    }
    const query = normalizeUserSearchText(raw?.query);
    if (!query || Array.from(query).length > 30) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Search text must be between 1 and 30 characters.',
      );
    }
    const requestedLimit = Number(raw?.limit);
    const limit = Math.max(1, Math.min(
      30,
      Number.isFinite(requestedLimit) ? Math.trunc(requestedLimit) : 20,
    ));
    const snapshot = await db().collection(COL.searchEntities)
      .where('searchTokens', 'array-contains', query)
      .limit(Math.min(100, limit * 4))
      .get();
    const organizations = snapshot.docs
      .filter((document) => document.get('entityType') === 'organization' &&
        document.get('isSearchable') === true &&
        (matchesUserSearch(document.get('name'), query) ||
          matchesUserSearch(document.get('handle'), query)))
      .sort((left, right) => {
        const score = userSearchRelevance(right.get('name'), query) -
          userSearchRelevance(left.get('name'), query);
        return score || left.id.localeCompare(right.id);
      })
      .slice(0, limit)
      .map((document) => ({
        organizationId: asString(document.get('entityId'), 128),
        name: asString(document.get('name'), 100),
        handle: asString(document.get('handle'), 40),
        organizationType: asString(document.get('organizationType'), 80),
        affiliation: asString(document.get('affiliation'), 160),
        activityArea: asString(document.get('activityArea'), 160),
        logoUrl: asString(document.get('logoUrl'), 2000),
        coverImageUrl: asString(document.get('coverImageUrl'), 2000),
        shortDescription: asString(
          document.get('shortDescription'),
          300,
        ),
        description: asString(document.get('description'), 2000),
        publicContact: asString(document.get('publicContact'), 320),
        websiteUrl: asString(document.get('websiteUrl'), 2000),
        verificationStatus: asString(
          document.get('verificationStatus'),
          40,
        ),
        partnerStatus: asString(document.get('partnerStatus'), 40),
      }));
    return {organizations};
  });

export const onOrganizationManagerAuthDeleted = functions.auth.user()
  .onDelete(async (user) => {
    const memberships = await db().collection(COL.organizationMemberships)
      .where('uid', '==', user.uid)
      .get();
    for (const membership of memberships.docs) {
      await db().runTransaction(async (transaction) => {
        const organizationId = asString(
          membership.get('organizationId'),
          128,
        );
        if (!organizationId) return;
        const organizationRef = db().collection(COL.organizations)
          .doc(organizationId);
        const searchRef = db().collection(COL.searchEntities)
          .doc(`organization_${organizationId}`);
        const organizationMemberships = db()
          .collection(COL.organizationMemberships)
          .where('organizationId', '==', organizationId);
        const [current, organization, relatedMemberships] =
          await Promise.all([
            transaction.get(membership.ref),
            transaction.get(organizationRef),
            transaction.get(organizationMemberships),
          ]);
        if (!current.exists || current.get('uid') !== user.uid ||
            current.get('status') !== 'active') return;
        const deletedManagerWasOwner = current.get('role') === 'owner';
        const hasAnotherActiveOwner = relatedMemberships.docs.some(
          (candidate) => candidate.id !== current.id &&
            candidate.get('status') === 'active' &&
            candidate.get('role') === 'owner',
        );
        const now = admin.firestore.FieldValue.serverTimestamp();
        transaction.update(membership.ref, {
          status: 'revoked',
          revokedReason: 'auth_user_deleted',
          revokedAt: now,
          updatedAt: now,
        });
        // Keep the organization and all authored content intact, but never
        // leave a publicly active organization without an owner. The operator
        // can issue a replacement owner invite from this recoverable state.
        if (deletedManagerWasOwner && !hasAnotherActiveOwner &&
            organization.exists) {
          transaction.update(organizationRef, {
            lifecycleStatus: 'awaiting_owner',
            isSearchable: false,
            updatedAt: now,
          });
          transaction.set(searchRef, {
            isSearchable: false,
            updatedAt: now,
          }, {merge: true});
        }
        const auditRef = db().collection(COL.organizationAuditLogs).doc();
        transaction.create(auditRef, {
          organizationId,
          action: 'manager_auth_deleted',
          actorUid: 'system',
          targetUid: user.uid,
          ownerRecoveryRequired:
            deletedManagerWasOwner && !hasAnotherActiveOwner,
          createdAt: now,
        });
      });
    }
  });

export async function approveOrganizationInviteIdentityForAdmin(
  inviteId: string,
  targetUid: string,
  operatorUid: string,
): Promise<void> {
  const normalizedInviteId = requireString(inviteId, 'inviteId', 128);
  const normalizedTargetUid = requireString(targetUid, 'targetUid', 128);
  const normalizedOperatorUid = await requirePlatformAdminUid(operatorUid);
  const store = db();
  const inviteRef = store.collection(COL.organizationInvites)
    .doc(normalizedInviteId);
  await store.runTransaction(async (transaction) => {
    const invite = await transaction.get(inviteRef);
    if (!invite.exists || invite.get('status') !== 'pending' ||
        invite.get('identityReviewRequestedByUid') !== normalizedTargetUid) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'The requested identity review is not pending for this user.',
      );
    }
    transaction.update(inviteRef, {
      identityReviewStatus: 'approved',
      identityReviewApprovedForUid: normalizedTargetUid,
      identityReviewApprovedByUid: normalizedOperatorUid,
      identityReviewApprovedAt:
        admin.firestore.FieldValue.serverTimestamp(),
    });
    const auditRef = store.collection(COL.organizationAuditLogs).doc();
    transaction.create(auditRef, {
      organizationId: asString(invite.get('organizationId'), 128),
      action: 'organization_invite_identity_approved',
      actorUid: normalizedOperatorUid,
      targetUid: normalizedTargetUid,
      inviteId: normalizedInviteId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

export async function inviteOrganizationOwnerForAdmin(args: {
  organizationId: string;
  recipientEmail: string;
  allowedLoginProviders: string[];
  requestId: string;
  operatorUid: string;
  resend: boolean;
}): Promise<{inviteId: string; invitationToken: string}> {
  const organizationId = requireString(
    args.organizationId,
    'organizationId',
    128,
  );
  const recipientEmail = normalizeEmail(args.recipientEmail);
  const providers = normalizeProviders(args.allowedLoginProviders);
  const requestId = requireString(args.requestId, 'REQUEST_ID', 120);
  const operatorUid = await requirePlatformAdminUid(args.operatorUid);
  const token = newInvitationToken();
  const identity = invitationIdentity(token);
  const store = db();
  const organizationRef = store.collection(COL.organizations)
    .doc(organizationId);
  const inviteRef = store.collection(COL.organizationInvites)
    .doc(identity.id);
  const requestRef = store.collection(COL.organizationProvisioning)
    .doc(requestDocumentId('owner_invite', requestId));
  const previousInvites = store.collection(COL.organizationInvites)
    .where('organizationId', '==', organizationId);
  await store.runTransaction(async (transaction) => {
    const [organization, previousRequest, currentInvites] =
      await Promise.all([
        transaction.get(organizationRef),
        transaction.get(requestRef),
        transaction.get(previousInvites),
      ]);
    if (!organization.exists ||
        !['awaiting_owner', 'active'].includes(
          asString(organization.get('lifecycleStatus'), 40),
        )) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'The organization cannot receive an owner invitation.',
      );
    }
    if (previousRequest.exists) {
      throw new functions.https.HttpsError(
        'already-exists',
        'REQUEST_ID was already used. No new invitation was created.',
      );
    }
    const pending = currentInvites.docs.filter(
      (document) => document.exists && document.get('status') === 'pending',
    );
    if (pending.length > 0 && !args.resend) {
      throw new functions.https.HttpsError(
        'already-exists',
        'A pending owner invitation already exists.',
      );
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    for (const previous of pending) {
      transaction.update(previous.ref, {
        status: 'cancelled',
        cancelledReason: 'replaced_by_operator',
        cancelledByUid: operatorUid,
        cancelledAt: now,
      });
    }
    transaction.create(inviteRef, inviteDocument(
      organizationId,
      operatorUid,
      recipientEmail,
      providers,
      identity.hash,
      requestRef.id,
    ));
    transaction.create(requestRef, {
      requestId,
      organizationId,
      inviteId: identity.id,
      status: 'invitation_created',
      requestedByUid: operatorUid,
      createdAt: now,
      updatedAt: now,
    });
    const auditRef = store.collection(COL.organizationAuditLogs).doc();
    transaction.create(auditRef, {
      organizationId,
      action: args.resend ?
        'organization_owner_invite_resent' :
        'organization_owner_invited',
      actorUid: operatorUid,
      targetUid: null,
      inviteId: identity.id,
      requestId,
      createdAt: now,
    });
  });
  return {inviteId: identity.id, invitationToken: token};
}

export async function cancelOrganizationInviteForAdmin(args: {
  organizationId: string;
  inviteId: string;
  reason?: string;
  requestId: string;
  operatorUid: string;
}): Promise<void> {
  const organizationId = requireString(
    args.organizationId,
    'organizationId',
    128,
  );
  const inviteId = requireString(args.inviteId, 'inviteId', 128);
  const requestId = requireString(args.requestId, 'REQUEST_ID', 120);
  const operatorUid = await requirePlatformAdminUid(args.operatorUid);
  const store = db();
  const inviteRef = store.collection(COL.organizationInvites).doc(inviteId);
  const receiptRef = store.collection(COL.organizationProvisioning)
    .doc(requestDocumentId('cancel_invite', requestId));
  await store.runTransaction(async (transaction) => {
    const [invite, receipt] = await Promise.all([
      transaction.get(inviteRef),
      transaction.get(receiptRef),
    ]);
    if (receipt.exists) return;
    if (!invite.exists ||
        invite.get('organizationId') !== organizationId) {
      throw new functions.https.HttpsError(
        'not-found',
        'Organization invitation not found.',
      );
    }
    if (invite.get('status') !== 'pending') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Only a pending invitation can be cancelled.',
      );
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(inviteRef, {
      status: 'cancelled',
      cancelledReason: asString(args.reason, 500) || 'cancelled_by_operator',
      cancelledByUid: operatorUid,
      cancelledAt: now,
      updatedAt: now,
    });
    transaction.create(receiptRef, {
      requestId,
      organizationId,
      inviteId,
      status: 'completed',
      operation: 'cancel_organization_invite',
      requestedByUid: operatorUid,
      createdAt: now,
      updatedAt: now,
    });
    transaction.create(store.collection(COL.organizationAuditLogs).doc(), {
      organizationId,
      action: 'organization_invite_cancelled',
      actorUid: operatorUid,
      targetUid: null,
      inviteId,
      requestId,
      createdAt: now,
    });
  });
}

export async function updateOrganizationForAdmin(args: {
  organizationId: string;
  profile?: Record<string, unknown>;
  privateProfile?: Record<string, unknown>;
  verificationStatus?: string;
  partnerStatus?: string;
  requestId: string;
  operatorUid: string;
}): Promise<void> {
  const organizationId = requireString(
    args.organizationId,
    'organizationId',
    128,
  );
  const operatorUid = await requirePlatformAdminUid(args.operatorUid);
  const requestId = requireString(args.requestId, 'REQUEST_ID', 120);
  const rawProfile = args.profile ?? {};
  const update = Object.keys(rawProfile).length > 0 ?
    editableOrganizationFields(rawProfile) : {};
  const governanceUpdate: Record<string, unknown> = {};
  if (args.verificationStatus != null) {
    const value = asString(args.verificationStatus, 40);
    if (!VERIFICATION_STATUSES.has(value)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Unsupported verification status.',
      );
    }
    governanceUpdate.verificationStatus = value;
  }
  if (args.partnerStatus != null) {
    const value = asString(args.partnerStatus, 40);
    if (!PARTNER_STATUSES.has(value)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Unsupported partner status.',
      );
    }
    governanceUpdate.partnerStatus = value;
  }
  const privateInput = args.privateProfile ?? {};
  const privateUpdate: Record<string, unknown> = {};
  if (Object.prototype.hasOwnProperty.call(privateInput, 'contactEmail')) {
    privateUpdate.contactEmail = normalizeEmail(privateInput.contactEmail);
  }
  if (Object.prototype.hasOwnProperty.call(
    privateInput,
    'ownerContactEmail',
  )) {
    privateUpdate.ownerContactEmail = normalizeEmail(
      privateInput.ownerContactEmail,
    );
  }
  if (Object.keys(update).length === 0 &&
      Object.keys(governanceUpdate).length === 0 &&
      Object.keys(privateUpdate).length === 0) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'At least one organization field is required.',
    );
  }
  const store = db();
  const organizationRef = store.collection(COL.organizations)
    .doc(organizationId);
  const privateRef = store.collection(COL.organizationPrivate)
    .doc(organizationId);
  const receiptRef = store.collection(COL.organizationProvisioning)
    .doc(requestDocumentId('organization_update', requestId));
  const searchRef = store.collection(COL.searchEntities)
    .doc(`organization_${organizationId}`);
  await store.runTransaction(async (transaction) => {
    const [organization, receipt] = await Promise.all([
      transaction.get(organizationRef),
      transaction.get(receiptRef),
    ]);
    if (!organization.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Organization not found.',
      );
    }
    if (receipt.exists) return;
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.update(organizationRef, {
      ...update,
      ...governanceUpdate,
      updatedAt: now,
    });
    if (Object.keys(privateUpdate).length > 0) {
      transaction.set(privateRef, {...privateUpdate, updatedAt: now}, {
        merge: true,
      });
    }
    const name = asString(update.name ?? organization.get('name'), 100);
    const handle = asString(organization.get('handle'), 40);
    transaction.set(searchRef, {
      name,
      handle,
      organizationType: asString(
        update.organizationType ?? organization.get('organizationType'),
        80,
      ),
      affiliation: asString(
        update.affiliation ?? organization.get('affiliation'),
        160,
      ),
      logoUrl: asString(update.logoUrl ?? organization.get('logoUrl'), 2000),
      verificationStatus: asString(
        governanceUpdate.verificationStatus ??
          organization.get('verificationStatus'),
        40,
      ),
      partnerStatus: asString(
        governanceUpdate.partnerStatus ?? organization.get('partnerStatus'),
        40,
      ),
      searchTokens: organizationSearchTokens(name, handle),
      updatedAt: now,
    }, {merge: true});
    transaction.create(receiptRef, {
      requestId,
      organizationId,
      status: 'completed',
      operation: 'update_organization',
      requestedByUid: operatorUid,
      createdAt: now,
      updatedAt: now,
    });
    const auditRef = store.collection(COL.organizationAuditLogs).doc();
    transaction.create(auditRef, {
      organizationId,
      action: 'organization_updated_by_platform',
      actorUid: operatorUid,
      targetUid: null,
      requestId,
      changedFields: [
        ...Object.keys(update),
        ...Object.keys(governanceUpdate),
        ...Object.keys(privateUpdate).map((field) => `private.${field}`),
      ].sort(),
      createdAt: now,
    });
  });
}

export async function setOrganizationLifecycleForAdmin(args: {
  organizationId: string;
  lifecycleStatus: 'suspended' | 'active';
  reason?: string;
  requestId: string;
  operatorUid: string;
}): Promise<void> {
  const organizationId = requireString(
    args.organizationId,
    'organizationId',
    128,
  );
  const operatorUid = await requirePlatformAdminUid(args.operatorUid);
  const requestId = requireString(args.requestId, 'REQUEST_ID', 120);
  const store = db();
  const organizationRef = store.collection(COL.organizations)
    .doc(organizationId);
  const privateRef = store.collection(COL.organizationPrivate)
    .doc(organizationId);
  const searchRef = store.collection(COL.searchEntities)
    .doc(`organization_${organizationId}`);
  const receiptRef = store.collection(COL.organizationProvisioning)
    .doc(requestDocumentId(`lifecycle_${args.lifecycleStatus}`, requestId));
  const owners = args.lifecycleStatus === 'active' ?
    store.collection(COL.organizationMemberships)
      .where('organizationId', '==', organizationId) : null;
  await store.runTransaction(async (transaction) => {
    const [organization, receipt, ownerMemberships] = await Promise.all([
      transaction.get(organizationRef),
      transaction.get(receiptRef),
      owners ? transaction.get(owners) : Promise.resolve(null),
    ]);
    if (!organization.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Organization not found.',
      );
    }
    if (receipt.exists) return;
    if (args.lifecycleStatus === 'active') {
      const activeOwner = ownerMemberships?.docs.some((membership) =>
        membership.get('status') === 'active' &&
        membership.get('role') === 'owner') === true;
      if (!activeOwner) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'An active owner is required before activation.',
        );
      }
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    const isActive = args.lifecycleStatus === 'active';
    transaction.update(organizationRef, {
      lifecycleStatus: args.lifecycleStatus,
      isSearchable: isActive,
      updatedAt: now,
      ...(isActive ? {publishedAt: now} : {}),
    });
    transaction.set(searchRef, {
      isSearchable: isActive,
      updatedAt: now,
    }, {merge: true});
    if (!isActive) {
      transaction.set(privateRef, {
        suspensionReason: asString(args.reason, 1000),
        suspendedAt: now,
        suspendedByUid: operatorUid,
        updatedAt: now,
      }, {merge: true});
    }
    transaction.create(receiptRef, {
      requestId,
      organizationId,
      status: 'completed',
      operation: `${args.lifecycleStatus}_organization`,
      requestedByUid: operatorUid,
      createdAt: now,
      updatedAt: now,
    });
    const auditRef = store.collection(COL.organizationAuditLogs).doc();
    transaction.create(auditRef, {
      organizationId,
      action: `organization_${args.lifecycleStatus}`,
      actorUid: operatorUid,
      targetUid: null,
      requestId,
      createdAt: now,
    });
  });
}

export async function transferOrganizationOwnerForAdmin(args: {
  organizationId: string;
  nextOwnerUid: string;
  requestId: string;
  operatorUid: string;
}): Promise<void> {
  const organizationId = requireString(
    args.organizationId,
    'organizationId',
    128,
  );
  const nextOwnerUid = requireString(args.nextOwnerUid, 'nextOwnerUid', 128);
  const operatorUid = await requirePlatformAdminUid(args.operatorUid);
  const requestId = requireString(args.requestId, 'REQUEST_ID', 120);
  const store = db();
  const memberships = store.collection(COL.organizationMemberships)
    .where('organizationId', '==', organizationId);
  const nextOwnerRef = store.collection(COL.organizationMemberships)
    .doc(membershipId(organizationId, nextOwnerUid));
  const receiptRef = store.collection(COL.organizationProvisioning)
    .doc(requestDocumentId('transfer_owner', requestId));
  const privateRef = store.collection(COL.organizationPrivate)
    .doc(organizationId);
  await store.runTransaction(async (transaction) => {
    const [nextOwner, receipt, currentMemberships] = await Promise.all([
      transaction.get(nextOwnerRef),
      transaction.get(receiptRef),
      transaction.get(memberships),
    ]);
    if (receipt.exists) return;
    if (!nextOwner.exists || nextOwner.get('status') !== 'active') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'The new owner must already have an active membership.',
      );
    }
    const currentOwners = currentMemberships.docs.filter((membership) =>
      membership.exists && membership.get('status') === 'active' &&
      membership.get('role') === 'owner');
    const now = admin.firestore.FieldValue.serverTimestamp();
    for (const owner of currentOwners) {
      if (owner.get('uid') !== nextOwnerUid) {
        transaction.update(owner.ref, {role: 'manager', updatedAt: now});
      }
    }
    transaction.update(nextOwnerRef, {role: 'owner', updatedAt: now});
    transaction.set(privateRef, {
      ownershipHistory: admin.firestore.FieldValue.arrayUnion({
        nextOwnerUid,
        changedByUid: operatorUid,
        changedAt: admin.firestore.Timestamp.now(),
        requestId,
      }),
      updatedAt: now,
    }, {merge: true});
    transaction.create(receiptRef, {
      requestId,
      organizationId,
      status: 'completed',
      operation: 'transfer_organization_owner',
      requestedByUid: operatorUid,
      createdAt: now,
      updatedAt: now,
    });
    const auditRef = store.collection(COL.organizationAuditLogs).doc();
    transaction.create(auditRef, {
      organizationId,
      action: 'organization_owner_transferred',
      actorUid: operatorUid,
      targetUid: nextOwnerUid,
      requestId,
      createdAt: now,
    });
  });
}

export async function updateOrganizationEntitlementsForAdmin(args: {
  organizationId: string;
  status: string;
  features?: Record<string, unknown>;
  requestId: string;
  operatorUid: string;
}): Promise<void> {
  const organizationId = requireString(
    args.organizationId,
    'organizationId',
    128,
  );
  const status = asString(args.status, 40);
  if (!ENTITLEMENT_STATUSES.has(status)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Unsupported entitlement status.',
    );
  }
  const featuresInput = args.features ?? {};
  if (typeof featuresInput !== 'object' || Array.isArray(featuresInput) ||
      Object.keys(featuresInput).length > 50) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Entitlement features must be a small object.',
    );
  }
  const features: Record<string, boolean> = {};
  for (const [key, rawValue] of Object.entries(featuresInput)) {
    const normalizedKey = asString(key, 60);
    if (!/^[a-z][a-z0-9_]*$/.test(normalizedKey) ||
        typeof rawValue !== 'boolean') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Entitlement features must use boolean snake_case keys.',
      );
    }
    features[normalizedKey] = rawValue;
  }
  const requestId = requireString(args.requestId, 'REQUEST_ID', 120);
  const operatorUid = await requirePlatformAdminUid(args.operatorUid);
  const store = db();
  const organizationRef = store.collection(COL.organizations)
    .doc(organizationId);
  const entitlementRef = store.collection(COL.organizationEntitlements)
    .doc(organizationId);
  const receiptRef = store.collection(COL.organizationProvisioning)
    .doc(requestDocumentId('update_entitlements', requestId));
  await store.runTransaction(async (transaction) => {
    const [organization, receipt] = await Promise.all([
      transaction.get(organizationRef),
      transaction.get(receiptRef),
    ]);
    if (!organization.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Organization not found.',
      );
    }
    if (receipt.exists) return;
    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.set(entitlementRef, {
      organizationId,
      status,
      features,
      updatedByUid: operatorUid,
      updatedAt: now,
    }, {merge: true});
    transaction.create(receiptRef, {
      requestId,
      organizationId,
      status: 'completed',
      operation: 'update_organization_entitlements',
      requestedByUid: operatorUid,
      createdAt: now,
      updatedAt: now,
    });
    transaction.create(store.collection(COL.organizationAuditLogs).doc(), {
      organizationId,
      action: 'organization_entitlements_updated',
      actorUid: operatorUid,
      targetUid: null,
      requestId,
      entitlementStatus: status,
      changedFeatures: Object.keys(features).sort(),
      createdAt: now,
    });
  });
}
