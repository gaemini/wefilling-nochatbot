export type SignupLanguage = 'ko' | 'en';

/** Returns null when recovery/login did not make an explicit locale choice. */
export function explicitSignupLanguage(raw: unknown): SignupLanguage | null {
  if (typeof raw !== 'string' || raw.trim().length === 0) return null;
  return raw.trim().toLowerCase().startsWith('ko') ? 'ko' : 'en';
}

/**
 * An active signup screen may correct an earlier login probe's default, while
 * startup recovery preserves the locale already stored for the pending uid.
 */
export function resolvePendingSignupLanguage(
  requested: SignupLanguage | null,
  existing: unknown,
): SignupLanguage {
  if (requested != null) return requested;
  return typeof existing === 'string' &&
    existing.trim().toLowerCase().startsWith('ko') ? 'ko' : 'en';
}

/** Resolves the request while remaining compatible with older app builds. */
export function resolvePendingSignupLanguageRequest({
  rawRequested,
  existing,
  userDocumentExists,
  explicitlySelected,
}: {
  rawRequested: unknown;
  existing: unknown;
  userDocumentExists: boolean;
  explicitlySelected: boolean;
}): SignupLanguage {
  const supplied = explicitSignupLanguage(rawRequested);
  return resolvePendingSignupLanguage(
    !userDocumentExists || explicitlySelected ? supplied : null,
    existing,
  );
}
