/**
 * The two secrets behind a report link, and the hashes that stand in for them at rest.
 *
 * The access token is 256 bits of randomness carried only in the URL of the recipient's email.
 * The one-time code is six digits, emailed to the address the link was issued to when the
 * recipient asks for it, and dead ten minutes later. Neither is ever stored: the row holds
 * SHA-256 of the token, and SHA-256 of token plus code. Salting the code with the token means
 * a copy of the table cannot be used to test codes offline without also holding the URL.
 *
 * Pure. No SOQL, no DML.
 */
public with sharing class TCMReadmissionAccessToken {

    public static final Integer CODE_LENGTH = 6;

    private static final Pattern TOKEN_SHAPE = Pattern.compile('^[0-9a-f]{64}$');
    private static final Pattern CODE_SHAPE = Pattern.compile('^[0-9]{6}$');

    /** 32 random bytes as 64 lowercase hex characters, which is URL-safe as it stands. */
    public static String mintToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }

    /** Six digits, zero padded, from the platform's secure random source. */
    public static String mintCode() {
        Integer n = Math.mod(Crypto.getRandomInteger(), 1000000);
        if (n < 0) {
            n = -n;
        }
        return String.valueOf(n).leftPad(CODE_LENGTH, '0');
    }

    public static String hashToken(String rawToken) {
        return sha256(rawToken);
    }

    public static String hashCode(String rawToken, String code) {
        return sha256(rawToken + ':' + code);
    }

    /** Anything that is not exactly 64 hex characters never reaches the database. */
    public static Boolean looksLikeToken(String value) {
        return value != null && TOKEN_SHAPE.matcher(value).matches();
    }

    public static Boolean looksLikeCode(String value) {
        return value != null && CODE_SHAPE.matcher(value).matches();
    }

    /**
     * Compares two hashes without short-circuiting on the first differing character, so the
     * time taken says nothing about how much of a guess was right.
     */
    public static Boolean matches(String expectedHash, String candidateHash) {
        if (expectedHash == null || candidateHash == null
            || expectedHash.length() != candidateHash.length()) {
            return false;
        }
        Integer difference = 0;
        for (Integer i = 0; i < expectedHash.length(); i++) {
            difference |= expectedHash.charAt(i) ^ candidateHash.charAt(i);
        }
        return difference == 0;
    }

    private static String sha256(String value) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(value))
        );
    }
}