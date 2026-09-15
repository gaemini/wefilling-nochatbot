#!/usr/bin/env node

/*
 * Platform-only organization lifecycle CLI.
 *
 * Dry-run is the default. Mutations require --apply, an exact project
 * confirmation and an Auth operator whose custom claims contain
 * {platformAdmin: true}. Raw invite tokens are never printed; a newly issued
 * link is written to an explicit owner-only file (0600).
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function arg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? String(process.argv[index + 1] || '').trim() : '';
}

function envOrArg(envName, flag) {
  return arg(flag) || String(process.env[envName] || '').trim();
}

function required(value, name) {
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function providers() {
  return required(
    envOrArg('ALLOWED_LOGIN_PROVIDERS', '--allowed-login-providers'),
    'ALLOWED_LOGIN_PROVIDERS',
  ).split(',').map((value) => value.trim()).filter(Boolean);
}

function redactedEmail(value) {
  const parts = String(value || '').split('@');
  if (parts.length !== 2) return 'invalid';
  return `${parts[0].slice(0, 1)}***@${parts[1]}`;
}

function reservePrivateInviteOutput(outputPath) {
  const resolved = path.resolve(outputPath);
  const parent = path.dirname(resolved);
  fs.mkdirSync(parent, {recursive: true, mode: 0o700});
  const descriptor = fs.openSync(
    resolved,
    fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY,
    0o600,
  );
  return {path: resolved, descriptor};
}

function writePrivateInvite(reservation, invitationToken) {
  const link = `wefilling://organization-invite?token=${
    encodeURIComponent(invitationToken)}`;
  try {
    fs.writeFileSync(reservation.descriptor, `${link}\n`, {encoding: 'utf8'});
    fs.fsyncSync(reservation.descriptor);
  } finally {
    fs.closeSync(reservation.descriptor);
  }
  fs.chmodSync(reservation.path, 0o600);
}

function removeEmptyReservedInvite(reservation) {
  if (!reservation) return;
  try {
    fs.closeSync(reservation.descriptor);
  } catch (_) {
    // The descriptor may already be closed after a completed write.
  }
  try {
    if (fs.statSync(reservation.path).size === 0) fs.unlinkSync(reservation.path);
  } catch (_) {
    // Never obscure the authoritative server error with local cleanup.
  }
}

async function verifyOperator(operatorUid) {
  const user = await admin.auth().getUser(operatorUid);
  if (user.customClaims?.platformAdmin !== true) {
    throw new Error('The operator does not have platformAdmin=true');
  }
  return user;
}

async function bootstrapPlatformAdmin(projectId, targetUid, apply) {
  const target = await admin.auth().getUser(targetUid);
  const claims = target.customClaims || {};
  const summary = {
    command: 'grant-platform-admin',
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    targetUid,
    existingPlatformAdmin: claims.platformAdmin === true,
    mergedClaimKeys: Object.keys(claims).sort(),
  };
  if (!apply) return summary;
  if (process.env.ALLOW_PLATFORM_ADMIN_BOOTSTRAP !== projectId) {
    throw new Error(
      'Set ALLOW_PLATFORM_ADMIN_BOOTSTRAP to the exact project ID for this one-time operation',
    );
  }
  await admin.auth().setCustomUserClaims(targetUid, {
    ...claims,
    platformAdmin: true,
  });
  return {...summary, existingPlatformAdmin: true};
}

async function authEmailSummary(email) {
  try {
    const user = await admin.auth().getUserByEmail(email);
    return {
      exists: true,
      disabled: user.disabled,
      providers: user.providerData
        .map((provider) => provider.providerId)
        .sort(),
    };
  } catch (error) {
    if (error?.code === 'auth/user-not-found') {
      return {exists: false, disabled: false, providers: []};
    }
    throw error;
  }
}

async function createDryRun(db, input) {
  const organizationModule = require('../lib/organization_accounts');
  const handle = organizationModule.normalizeOrganizationHandle(input.handle);
  const [
    identity,
    legacyNickname,
    organizationsByHandle,
    organizationsByName,
    ownerAuth,
  ] = await Promise.all([
    db.collection('identity_handles').doc(handle).get(),
    db.collection('nicknameClaims').doc(handle).get(),
    db.collection('organizations').where('handle', '==', handle).limit(2).get(),
    db.collection('organizations').where('name', '==', input.name).limit(10).get(),
    authEmailSummary(input.ownerContactEmail),
  ]);
  return {
    organizationName: input.name,
    handle: `@${handle}`,
    ownerContact: redactedEmail(input.ownerContactEmail),
    allowedLoginProviders: input.allowedLoginProviders,
    duplicateIdentityHandle: identity.exists,
    duplicateLegacyNickname: legacyNickname.exists,
    duplicateOrganizationHandles: organizationsByHandle.size,
    sameDisplayNameOrganizations: organizationsByName.size,
    existingOwnerAuthAccount: ownerAuth,
    initialLifecycleStatus: 'awaiting_owner',
    initialIsSearchable: false,
    documents: [
      'organizations/{orgId}',
      'organization_private/{orgId}',
      'organization_entitlements/{orgId}',
      'organization_invites/{inviteId}',
      'organization_provisioning/{requestId}',
      'identity_handles/{normalizedHandle}',
      'organization_audit_logs/{logId}',
    ],
  };
}

async function main() {
  const command = process.argv[2] || '';
  const projectId = required(
    envOrArg('FIREBASE_PROJECT_ID', '--project'),
    'FIREBASE_PROJECT_ID',
  );
  const confirmedProject = arg('--confirm-project');
  const targetEnvironment = required(
    envOrArg('TARGET_ENVIRONMENT', '--environment'),
    'TARGET_ENVIRONMENT',
  );
  const apply = process.argv.includes('--apply');
  if (apply && confirmedProject !== projectId) {
    throw new Error('--apply requires an identical --confirm-project');
  }
  admin.initializeApp({projectId});
  const db = admin.firestore();

  if (command === 'grant-platform-admin') {
    const targetUid = required(
      envOrArg('TARGET_UID', '--target-uid'),
      'TARGET_UID',
    );
    const result = await bootstrapPlatformAdmin(projectId, targetUid, apply);
    process.stdout.write(`${JSON.stringify({
      ...result,
      targetEnvironment,
    }, null, 2)}\n`);
    return;
  }

  const operatorUid = required(
    envOrArg('PLATFORM_ADMIN_UID', '--operator-uid'),
    'PLATFORM_ADMIN_UID',
  );
  await verifyOperator(operatorUid);
  const organizationModule = require('../lib/organization_accounts');
  const requestId = required(
    envOrArg('REQUEST_ID', '--request-id'),
    'REQUEST_ID',
  );
  const base = {
    command,
    mode: apply ? 'apply' : 'dry-run',
    projectId,
    targetEnvironment,
    requestId,
  };

  if (command === 'create-organization') {
    const input = {
      requestId,
      name: required(envOrArg('ORG_NAME', '--org-name'), 'ORG_NAME'),
      handle: required(envOrArg('ORG_HANDLE', '--org-handle'), 'ORG_HANDLE'),
      organizationType: required(
        envOrArg('ORG_TYPE', '--org-type'),
        'ORG_TYPE',
      ),
      affiliation: envOrArg('ORG_AFFILIATION', '--org-affiliation'),
      description: envOrArg('ORG_DESCRIPTION', '--org-description'),
      logoUrl: envOrArg('ORG_LOGO', '--org-logo'),
      contactEmail: required(
        envOrArg('ORG_CONTACT_EMAIL', '--org-contact-email'),
        'ORG_CONTACT_EMAIL',
      ),
      ownerContactEmail: required(
        envOrArg('ORG_OWNER_CONTACT_EMAIL', '--owner-contact-email'),
        'ORG_OWNER_CONTACT_EMAIL',
      ),
      allowedLoginProviders: providers(),
      targetEnvironment,
    };
    const preview = await createDryRun(db, input);
    if (!apply) {
      process.stdout.write(`${JSON.stringify({...base, preview}, null, 2)}\n`);
      return;
    }
    const reservedInviteFile = reservePrivateInviteOutput(
      required(arg('--invite-output'), '--invite-output'),
    );
    let result;
    try {
      result = await organizationModule.provisionOrganizationForAdmin(
        input,
        operatorUid,
      );
    } catch (error) {
      removeEmptyReservedInvite(reservedInviteFile);
      throw error;
    }
    let invitationFile = '';
    if (result.invitationToken) {
      writePrivateInvite(reservedInviteFile, result.invitationToken);
      invitationFile = reservedInviteFile.path;
    } else {
      removeEmptyReservedInvite(reservedInviteFile);
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId: result.organizationId,
      inviteId: result.inviteId,
      lifecycleStatus: result.lifecycleStatus,
      provisioningStatus: result.provisioningStatus,
      reused: result.reused,
      invitationFile: invitationFile || 'not-created-on-idempotent-retry',
    }, null, 2)}\n`);
    return;
  }

  const organizationId = required(
    envOrArg('ORGANIZATION_ID', '--organization-id'),
    'ORGANIZATION_ID',
  );

  if (command === 'invite-organization-owner' ||
      command === 'resend-organization-invite') {
    const recipientEmail = required(
      envOrArg('ORG_OWNER_CONTACT_EMAIL', '--owner-contact-email'),
      'ORG_OWNER_CONTACT_EMAIL',
    );
    const allowedLoginProviders = providers();
    if (!apply) {
      process.stdout.write(`${JSON.stringify({
        ...base,
        organizationId,
        ownerContact: redactedEmail(recipientEmail),
        allowedLoginProviders,
        replacesPendingInvite:
          command === 'resend-organization-invite',
      }, null, 2)}\n`);
      return;
    }
    const invitationFile = reservePrivateInviteOutput(
      required(arg('--invite-output'), '--invite-output'),
    );
    let result;
    try {
      result = await organizationModule
        .inviteOrganizationOwnerForAdmin({
          organizationId,
          recipientEmail,
          allowedLoginProviders,
          requestId,
          operatorUid,
          resend: command === 'resend-organization-invite',
        });
    } catch (error) {
      removeEmptyReservedInvite(invitationFile);
      throw error;
    }
    writePrivateInvite(invitationFile, result.invitationToken);
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      inviteId: result.inviteId,
      invitationFile: invitationFile.path,
    }, null, 2)}\n`);
    return;
  }

  if (command === 'update-organization') {
    const profile = {};
    const mapping = [
      ['ORG_NAME', '--org-name', 'name'],
      ['ORG_TYPE', '--org-type', 'organizationType'],
      ['ORG_AFFILIATION', '--org-affiliation', 'affiliation'],
      ['ORG_DESCRIPTION', '--org-description', 'description'],
      ['ORG_LOGO', '--org-logo', 'logoUrl'],
      ['ORG_ACTIVITY_AREA', '--activity-area', 'activityArea'],
      ['ORG_COVER_IMAGE', '--cover-image', 'coverImageUrl'],
      ['ORG_WEBSITE', '--website', 'websiteUrl'],
    ];
    for (const [environmentKey, flag, field] of mapping) {
      const value = envOrArg(environmentKey, flag);
      if (value) profile[field] = value;
    }
    const verificationStatus = envOrArg(
      'ORG_VERIFICATION_STATUS',
      '--verification-status',
    );
    const partnerStatus = envOrArg(
      'ORG_PARTNER_STATUS',
      '--partner-status',
    );
    if (Object.keys(profile).length === 0 &&
        !verificationStatus && !partnerStatus) {
      throw new Error('At least one organization profile field is required');
    }
    if (apply) {
      await organizationModule.updateOrganizationForAdmin({
        organizationId,
        profile,
        ...(verificationStatus && {verificationStatus}),
        ...(partnerStatus && {partnerStatus}),
        requestId,
        operatorUid,
      });
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      changedFields: [
        ...Object.keys(profile),
        ...(verificationStatus ? ['verificationStatus'] : []),
        ...(partnerStatus ? ['partnerStatus'] : []),
      ].sort(),
    }, null, 2)}\n`);
    return;
  }

  if (command === 'cancel-organization-invite') {
    const inviteId = required(arg('--invite-id'), '--invite-id');
    if (apply) {
      await organizationModule.cancelOrganizationInviteForAdmin({
        organizationId,
        inviteId,
        reason: arg('--reason'),
        requestId,
        operatorUid,
      });
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      inviteId,
      status: apply ? 'cancelled' : 'pending_dry_run',
    }, null, 2)}\n`);
    return;
  }

  if (command === 'update-organization-entitlements') {
    const status = required(
      envOrArg('ORG_ENTITLEMENT_STATUS', '--entitlement-status'),
      'ORG_ENTITLEMENT_STATUS',
    );
    const rawFeatures = envOrArg(
      'ORG_ENTITLEMENT_FEATURES_JSON',
      '--features-json',
    ) || '{}';
    let features;
    try {
      features = JSON.parse(rawFeatures);
    } catch (_) {
      throw new Error('ORG_ENTITLEMENT_FEATURES_JSON must be valid JSON');
    }
    if (!features || Array.isArray(features) || typeof features !== 'object') {
      throw new Error('ORG_ENTITLEMENT_FEATURES_JSON must be a JSON object');
    }
    if (apply) {
      await organizationModule.updateOrganizationEntitlementsForAdmin({
        organizationId,
        status,
        features,
        requestId,
        operatorUid,
      });
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      entitlementStatus: status,
      changedFeatureKeys: Object.keys(features).sort(),
    }, null, 2)}\n`);
    return;
  }

  if (command === 'suspend-organization' ||
      command === 'activate-organization') {
    const lifecycleStatus = command === 'suspend-organization' ?
      'suspended' : 'active';
    if (apply) {
      await organizationModule.setOrganizationLifecycleForAdmin({
        organizationId,
        lifecycleStatus,
        reason: arg('--reason'),
        requestId,
        operatorUid,
      });
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      lifecycleStatus,
    }, null, 2)}\n`);
    return;
  }

  if (command === 'transfer-organization-owner') {
    const nextOwnerUid = required(
      envOrArg('NEXT_OWNER_UID', '--next-owner-uid'),
      'NEXT_OWNER_UID',
    );
    if (apply) {
      await organizationModule.transferOrganizationOwnerForAdmin({
        organizationId,
        nextOwnerUid,
        requestId,
        operatorUid,
      });
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      nextOwnerUid,
    }, null, 2)}\n`);
    return;
  }

  if (command === 'approve-organization-invite') {
    const inviteId = required(arg('--invite-id'), '--invite-id');
    const targetUid = required(arg('--target-uid'), '--target-uid');
    if (apply) {
      await organizationModule.approveOrganizationInviteIdentityForAdmin(
        inviteId,
        targetUid,
        operatorUid,
      );
    }
    process.stdout.write(`${JSON.stringify({
      ...base,
      organizationId,
      inviteId,
      targetUid,
      status: apply ? 'approved' : 'pending_dry_run',
    }, null, 2)}\n`);
    return;
  }

  throw new Error(
    'Unknown command. Use create-organization, invite-organization-owner, resend-organization-invite, cancel-organization-invite, update-organization, update-organization-entitlements, suspend-organization, activate-organization, transfer-organization-owner, approve-organization-invite, or grant-platform-admin.',
  );
}

main().catch((error) => {
  process.stderr.write(`${error?.message || error}\n`);
  process.exitCode = 1;
});
