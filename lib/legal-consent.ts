export const LEGAL_DOCUMENT_VERSION = "2026-08-21";

export function normalizeInternalPath(candidate: string | null | undefined): string {
  const fallback = "/dashboard";
  if (!candidate || !candidate.startsWith("/") || /[\u0000-\u001f\u007f]/.test(candidate)) {
    return fallback;
  }

  try {
    const base = new URL("https://hyn-view.invalid");
    const resolved = new URL(candidate, base);
    if (resolved.origin !== base.origin || !resolved.pathname.startsWith("/")) {
      return fallback;
    }
    return `${resolved.pathname}${resolved.search}${resolved.hash}`;
  } catch {
    return fallback;
  }
}

export type PasswordSignUpRequest = {
  email: string;
  password: string;
  options: {
    emailRedirectTo: string;
    data: {
      legal_terms_version: string;
      legal_terms_accepted_at: string;
      legal_terms_url: string;
      privacy_notice_url: string;
    };
  };
};

export function buildPasswordSignUpRequest({
  email,
  password,
  emailRedirectTo,
  acceptedTerms,
  acceptedAt = new Date(),
}: {
  email: string;
  password: string;
  emailRedirectTo: string;
  acceptedTerms: boolean;
  acceptedAt?: Date;
}): PasswordSignUpRequest {
  if (!acceptedTerms) {
    throw new Error("You must accept the Terms of Use and acknowledge the Privacy Notice.");
  }

  return {
    email: email.trim(),
    password,
    options: {
      emailRedirectTo,
      data: {
        legal_terms_version: LEGAL_DOCUMENT_VERSION,
        legal_terms_accepted_at: acceptedAt.toISOString(),
        legal_terms_url: "https://www.hyn-view.in/terms",
        privacy_notice_url: "https://www.hyn-view.in/privacy",
      },
    },
  };
}
