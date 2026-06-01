/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : candidateLoginRestResource
 * Author          : <YourName>
 * Created Date    : Mar 25, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 25, 2026
 * Description     : REST endpoint for candidate login. Validates email + password
 *                   against the Registration_Request__c record, and returns an
 *                   ephemeral session token on success.
 *                   ⚠️ Session token is NOT stored anywhere in Salesforce.
 *
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 25, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@RestResource(urlMapping='/candidateLogin/*')
global with sharing class candidateLoginRestResource {

    // ─── Request Wrapper ───────────────────────────────────────────────────────

    global class LoginRequest {
        public String email;
        public String password;
    }

    // ─── Response Wrapper ─────────────────────────────────────────────────────

    global class LoginResponse {
        public Boolean                  success;
        public String                   message;
        public String                   registrationId;
        public String                   contactId;
        public CandidateProfile         candidate;      // safe profile (no password hash)

        /**
         * sessionToken — Generated on-the-fly using a cryptographically secure
         * random value (SHA-256 digest of AES-256 random key + contactId + regId + epoch).
         *
         * ⚠️  IMPORTANT: This token is NOT persisted anywhere in Salesforce
         *     (no Custom Object, no Custom Setting, no Platform Cache, no field).
         *     The caller is responsible for storing and managing this token
         *     on their side (e.g. in their own session store / Redis / JWT).
         *     Salesforce has zero knowledge of this token after the response is sent.
         */
        public String                   sessionToken;
        public String                   errorDetails;
    }

    // ─── Safe Profile DTO (excludes sensitive fields like Password_Hash__c) ───

    global class CandidateProfile {
        public String   registrationId;
        public String   contactId;
        public String   name;
        public String   firstName;
        public String   lastName;
        public String   email;
        public String   phone;
        public String   status;
        public Boolean  agreedToTerms;
        public String   termsAgreedDate;
        public String   registrationType;
        public String   createdDate;
        public String   lastModifiedDate;

        public CandidateProfile(Registration_Request__c reg) {
            this.registrationId   = reg.Id;
            this.contactId        = reg.Contact__c;
            this.name         = reg.Full_Name__c;
            this.firstName        = reg.First_Name__c;
            this.lastName         = reg.Last_Name__c;
            this.email            = reg.Email__c;
            this.phone            = reg.Contact__r != null ? reg.Contact__r.Phone : null;
            this.status           = reg.Status__c;
            this.agreedToTerms    = reg.Agreed_To_Terms__c;
            this.termsAgreedDate  = reg.Terms_Agreed_Date__c != null
                                        ? String.valueOf(reg.Terms_Agreed_Date__c) : null;
            this.registrationType = reg.Registration_Type__c;
            this.createdDate      = String.valueOf(reg.CreatedDate);
            this.lastModifiedDate = String.valueOf(reg.LastModifiedDate);
        }
    }

    // ─── POST: Candidate Login ─────────────────────────────────────────────────

    @HttpPost
    global static LoginResponse login() {

        RestRequest   req  = RestContext.request;
        LoginResponse resp = new LoginResponse();

        try {
            // 1. Deserialise request body
            LoginRequest reqBody = (LoginRequest)
                JSON.deserialize(req.requestBody.toString(), LoginRequest.class);

            // 2. Validate required fields
            validateRequest(reqBody);

            // 3. Look up Registration record by email + Registration_Type__c
            //    Password_Hash__c is fetched for verification — never returned in response
            List<Registration_Request__c> records = [
                SELECT
                    Id,
                    Full_Name__c,
                    First_Name__c,
                    Last_Name__c,
                    Email__c,
                    Password_Hash__c,        // used for verification only — not in response
                    Status__c,
                    Agreed_To_Terms__c,
                    Terms_Agreed_Date__c,
                    Registration_Type__c,
                    IP_Address__c,
                    Contact__c,
                    Contact__r.Id,
                    Contact__r.FirstName,
                    Contact__r.LastName,
                    Contact__r.Email,
                    Contact__r.Phone,
                    CreatedDate,
                    LastModifiedDate
                FROM Registration_Request__c
                WHERE Email__c             = :reqBody.email
                  AND Contact__r.RecordType.DeveloperName = 'R_ATS_Candidate'
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            // 4. No account found → generic error (avoid user enumeration)
            if (records.isEmpty()) {
                throw new LoginException('Invalid email or password.');
            }

            Registration_Request__c reg = records[0];

            // 5. Verify account is active
            if (reg.Status__c == 'Rejected' || reg.Status__c == 'Suspended') {
                throw new LoginException('Your account has been ' + reg.Status__c.toLowerCase()
                    + '. Please contact support.');
            }

            // 6. Verify password against stored hash
            if (!verifyPassword(reqBody.password, reg.Password_Hash__c)) {
                throw new LoginException('Invalid email or password.');
            }

            // 7. Generate ephemeral session token — NOT stored in Salesforce
            String sessionToken = generateSessionToken(reg.Contact__c, reg.Id);

            // 8. Build safe candidate profile (Password_Hash__c excluded)
            CandidateProfile profile = new CandidateProfile(reg);

            // 9. Build success response
            resp.success        = true;
            resp.message        = 'Login successful.';
            resp.registrationId = reg.Id;
            resp.contactId      = reg.Contact__c;
            resp.candidate      = profile;
            resp.sessionToken   = sessionToken;  // ephemeral — see field javadoc above

            RestContext.response.statusCode = 200;

        } catch (LoginException le) {
            resp.success      = false;
            resp.message      = le.getMessage();
            resp.errorDetails = le.getMessage();
            RestContext.response.statusCode = 401;

        } catch (JSONException je) {
            resp.success      = false;
            resp.message      = 'Invalid request format.';
            resp.errorDetails = je.getMessage();
            RestContext.response.statusCode = 400;

        } catch (Exception e) {
            resp.success      = false;
            resp.message      = 'An unexpected error occurred.';
            resp.errorDetails = e.getMessage();
            RestContext.response.statusCode = 500;
        }

        return resp;
    }

    // ─── Helper: Validate required fields ─────────────────────────────────────

    private static void validateRequest(LoginRequest req) {
        List<String> errors = new List<String>();

        if (String.isBlank(req.email))    errors.add('email is required.');
        if (String.isBlank(req.password)) errors.add('password is required.');

        if (!errors.isEmpty()) {
            throw new LoginException(String.join(errors, ' | '));
        }
    }

    // ─── Helper: Verify password against stored salt:hash ─────────────────────
    /**
     * Replicates the same hashing logic used during registration:
     *   storedHash format → "<16-char salt>:<base64 SHA-256 digest>"
     * Extracts the salt, re-hashes the candidate input, and compares.
     */
    private static Boolean verifyPassword(String candidatePassword, String storedHash) {
        if (String.isBlank(storedHash) || !storedHash.contains(':')) {
            return false;
        }

        List<String> parts = storedHash.split(':', 2);
        String salt        = parts[0];
        String savedDigest = parts[1];

        Blob   inputBlob   = Blob.valueOf(salt + candidatePassword);
        Blob   hashBlob    = Crypto.generateDigest('SHA-256', inputBlob);
        String inputDigest = EncodingUtil.base64Encode(hashBlob);

        // Constant-time string comparison to prevent timing attacks
        return constantTimeEquals(inputDigest, savedDigest);
    }

    // ─── Helper: Constant-time string comparison ───────────────────────────────
    /**
     * Compares two strings in O(n) time regardless of where they differ.
     * Prevents timing-based side-channel attacks on password verification.
     */
    private static Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null || a.length() != b.length()) {
            return false;
        }
        Integer result = 0;
        for (Integer i = 0; i < a.length(); i++) {
            result |= (a.charAt(i) ^ b.charAt(i));
        }
        return result == 0;
    }

    // ─── Helper: Generate ephemeral session token ──────────────────────────────
    /**
     * Produces a cryptographically secure, URL-safe session token by hashing:
     *   SHA-256( AES-256 random key + contactId + registrationId + epoch millis )
     *
     * ⚠️  NOT stored anywhere in Salesforce. This method only returns the token
     *     to the caller. Validation / expiry / revocation must be handled entirely
     *     by the consuming application (e.g. in their own auth service or Redis store).
     */
    private static String generateSessionToken(String contactId, String regId) {
        String rawPayload = EncodingUtil.base64Encode(Crypto.generateAesKey(256))
                          + contactId
                          + regId
                          + String.valueOf(DateTime.now().getTime());

        Blob   tokenBlob  = Crypto.generateDigest('SHA-256', Blob.valueOf(rawPayload));
        return EncodingUtil.convertToHex(tokenBlob);
    }

    // ─── Custom Exception ──────────────────────────────────────────────────────

    global class LoginException extends Exception {}
}