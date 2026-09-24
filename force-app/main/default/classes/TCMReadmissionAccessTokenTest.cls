/** The secrets and hashes behind a report link: shape, randomness, and comparison. */
@IsTest
private class TCMReadmissionAccessTokenTest {

    @IsTest
    static void tokensAre64HexCharactersAndNeverRepeat() {
        Set<String> seen = new Set<String>();
        for (Integer i = 0; i < 20; i++) {
            String token = TCMReadmissionAccessToken.mintToken();
            System.assert(TCMReadmissionAccessToken.looksLikeToken(token), token);
            System.assert(seen.add(token), 'duplicate token');
        }
        System.assert(!TCMReadmissionAccessToken.looksLikeToken(null));
        System.assert(!TCMReadmissionAccessToken.looksLikeToken(''));
        System.assert(!TCMReadmissionAccessToken.looksLikeToken('abc'));
        System.assert(!TCMReadmissionAccessToken.looksLikeToken('G'.repeat(64)), 'not hex');
        System.assert(!TCMReadmissionAccessToken.looksLikeToken('A'.repeat(64)), 'lowercase only');
        System.assert(!TCMReadmissionAccessToken.looksLikeToken('a'.repeat(63)));
        System.assert(!TCMReadmissionAccessToken.looksLikeToken('a'.repeat(65)));
    }

    @IsTest
    static void codesAreSixDigitsZeroPadded() {
        for (Integer i = 0; i < 20; i++) {
            String code = TCMReadmissionAccessToken.mintCode();
            System.assert(TCMReadmissionAccessToken.looksLikeCode(code), code);
        }
        System.assert(TCMReadmissionAccessToken.looksLikeCode('000042'));
        System.assert(!TCMReadmissionAccessToken.looksLikeCode('42'));
        System.assert(!TCMReadmissionAccessToken.looksLikeCode('1234567'));
        System.assert(!TCMReadmissionAccessToken.looksLikeCode('12a456'));
        System.assert(!TCMReadmissionAccessToken.looksLikeCode(null));
    }

    @IsTest
    static void hashesAreDeterministicAndSaltedByTheToken() {
        String token = TCMReadmissionAccessToken.mintToken();
        String other = TCMReadmissionAccessToken.mintToken();

        System.assertEquals(
            TCMReadmissionAccessToken.hashToken(token), TCMReadmissionAccessToken.hashToken(token)
        );
        System.assertEquals(64, TCMReadmissionAccessToken.hashToken(token).length());
        System.assertNotEquals(token, TCMReadmissionAccessToken.hashToken(token), 'not identity');
        System.assertNotEquals(
            TCMReadmissionAccessToken.hashToken(token), TCMReadmissionAccessToken.hashToken(other)
        );

        System.assertEquals(
            TCMReadmissionAccessToken.hashCode(token, '123456'),
            TCMReadmissionAccessToken.hashCode(token, '123456')
        );
        System.assertNotEquals(
            TCMReadmissionAccessToken.hashCode(token, '123456'),
            TCMReadmissionAccessToken.hashCode(token, '123457'),
            'one digit changes the hash'
        );
        System.assertNotEquals(
            TCMReadmissionAccessToken.hashCode(token, '123456'),
            TCMReadmissionAccessToken.hashCode(other, '123456'),
            'the same code under another token is a different hash, so a stolen table cannot ' +
            'be tested offline without the URL'
        );
    }

    @IsTest
    static void comparisonIsExactAndSafeOnBadInput() {
        String a = TCMReadmissionAccessToken.hashToken('a');
        String b = TCMReadmissionAccessToken.hashToken('b');
        System.assert(TCMReadmissionAccessToken.matches(a, a));
        System.assert(!TCMReadmissionAccessToken.matches(a, b));
        System.assert(!TCMReadmissionAccessToken.matches(a, a.left(63)));
        System.assert(!TCMReadmissionAccessToken.matches(a, a + '0'));
        System.assert(!TCMReadmissionAccessToken.matches(null, a));
        System.assert(!TCMReadmissionAccessToken.matches(a, null));
        System.assert(!TCMReadmissionAccessToken.matches(null, null));
    }
}