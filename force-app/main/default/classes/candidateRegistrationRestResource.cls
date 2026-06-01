/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : candidateRegistrationRestResource
 * Author          : <YourName>
 * Created Date    : Mar 25, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 25, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 25, 2026  │ <YourName>   │ Initial version
 *  Mar 25, 2026  │ <YourName>   │ Added ephemeral session token in response (not stored in Salesforce)
 *  Mar 26, 2026  │ <YourName>   │ Replaced raw Registration_Request__c in response with safe CandidateProfile DTO
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

@RestResource(urlMapping='/candidateRegistration/*')
global with sharing class candidateRegistrationRestResource {

    // ─── Request Wrapper ───────────────────────────────────────────────────────

    global class RegistrationRequest {
        public String  firstName;
        public String  lastName;
        public String  email;
        public String  password;
        public Boolean agreeTerms;
    }

    // ─── Response Wrapper ─────────────────────────────────────────────────────

    global class RegistrationResponse {
        public Boolean           success;
        public String            message;
        public String            registrationId;
        public String            contactId;
        public CandidateProfile  candidate;      // ← safe DTO (no Password_Hash__c)

        /**
         * sessionToken — Generated on-the-fly using a cryptographically secure
         * random value (SHA-256 digest of AES-256 random key + timestamp).
         *
         * ⚠️  IMPORTANT: This token is NOT persisted anywhere in Salesforce
         *     (no Custom Object, no Custom Setting, no Platform Cache).
         *     The caller is responsible for storing and managing this token
         *     on their side (e.g. in their own session store / Redis / JWT).
         *     Salesforce has zero knowledge of this token after the response
         *     is sent.
         */
        public String            sessionToken;
        public String            errorDetails;
    }

    // ─── Safe Candidate Profile DTO ───────────────────────────────────────────
    // Mirrors CandidateProfile in candidateLoginRestResource.
    // Password_Hash__c is intentionally excluded — it must NEVER appear in any response.

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
            this.name             = reg.Full_Name__c;
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

    // ─── POST: Create Contact + Registration ──────────────────────────────────

    @HttpPost
    global static RegistrationResponse createRegistration() {

        RestRequest          req  = RestContext.request;
        RegistrationResponse resp = new RegistrationResponse();

        try {
            // 1. Deserialise request body
            RegistrationRequest reqBody = (RegistrationRequest)
                JSON.deserialize(req.requestBody.toString(), RegistrationRequest.class);

            // 2. Validate required fields
            validateRequest(reqBody);

            Savepoint sp = Database.setSavepoint();

            try {
                // 3. Create Contact
                Contact con = new Contact(
                    FirstName = reqBody.firstName,
                    LastName  = reqBody.lastName,
                    RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                    .get('R_ATS_Candidate').getRecordTypeId(),
                    Email     = reqBody.email
                );
                insert con;

                // 4. Create Registration record and link to Contact
                Registration_Request__c reg = new Registration_Request__c(
                    Full_Name__c         = reqBody.firstName + ' ' + reqBody.lastName,
                    First_Name__c        = reqBody.firstName,
                    Last_Name__c         = reqBody.lastName,
                    Email__c             = reqBody.email,
                    Password_Hash__c     = hashPassword(reqBody.password),
                    Status__c            = 'Pending',
                    Agreed_To_Terms__c   = reqBody.agreeTerms,
                    Terms_Agreed_Date__c = DateTime.now(),
                    Registration_Type__c = 'Candidate',
                    IP_Address__c        = RestContext.request.headers.get('X-Forwarded-For'),
                    Contact__c           = con.Id
                );
                insert reg;

                // 5. Re-query full Registration record with all fields
                Registration_Request__c fullReg = queryFullRegistration(reg.Id);

                // 6. Generate ephemeral session token — NOT stored in Salesforce
                String sessionToken = generateSessionToken(con.Id, reg.Id);

                // 7. Build success response using safe CandidateProfile DTO
                resp.success        = true;
                resp.message        = 'Registration created successfully.';
                resp.registrationId = reg.Id;
                resp.contactId      = con.Id;
                resp.candidate      = new CandidateProfile(fullReg);  // ← DTO, not raw SObject
                resp.sessionToken   = sessionToken;

                RestContext.response.statusCode = 201;

            } catch (Exception inr) {
                Database.rollback(sp);
                throw inr;
            }

        } catch (RegistrationException re) {
            resp.success      = false;
            resp.message      = re.getMessage();
            resp.errorDetails = re.getMessage();
            RestContext.response.statusCode = 400;

        } catch (DmlException de) {
            resp.success      = false;
            resp.message      = 'Database error occurred.';
            resp.errorDetails = de.getDmlMessage(0);
            RestContext.response.statusCode = 500;

        } catch (Exception e) {
            resp.success      = false;
            resp.message      = 'An unexpected error occurred.';
            resp.errorDetails = e.getMessage();
            RestContext.response.statusCode = 500;
        }

        return resp;
    }

    // ─── GET: Fetch existing Registration by Id ────────────────────────────────

    @HttpGet
    global static RegistrationResponse getRegistration() {

        RegistrationResponse resp = new RegistrationResponse();
        String registrationId = RestContext.request.params.get('id');

        try {
            if (String.isBlank(registrationId)) {
                throw new RegistrationException('Query parameter "id" is required.');
            }

            Registration_Request__c fullReg = queryFullRegistration(registrationId);

            if (fullReg == null) {
                throw new RegistrationException('Registration not found for Id: ' + registrationId);
            }

            resp.success        = true;
            resp.message        = 'Registration retrieved successfully.';
            resp.registrationId = fullReg.Id;
            resp.contactId      = fullReg.Contact__c;
            resp.candidate      = new CandidateProfile(fullReg);  // ← DTO, not raw SObject
            // Note: sessionToken is intentionally null on GET — tokens are only
            // issued at registration time and are never re-issued or stored here.
            RestContext.response.statusCode = 200;

        } catch (RegistrationException re) {
            resp.success      = false;
            resp.message      = re.getMessage();
            resp.errorDetails = re.getMessage();
            RestContext.response.statusCode = 400;

        } catch (Exception e) {
            resp.success      = false;
            resp.message      = 'An unexpected error occurred.';
            resp.errorDetails = e.getMessage();
            RestContext.response.statusCode = 500;
        }

        return resp;
    }

    // ─── Helper: Query full Registration record ────────────────────────────────

    private static Registration_Request__c queryFullRegistration(String regId) {
        List<Registration_Request__c> regs = [
            SELECT
                Id,
                Full_Name__c,
                First_Name__c,
                Last_Name__c,
                Email__c,
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
            WHERE Id = :regId
            LIMIT 1
        ];
        return regs.isEmpty() ? null : regs[0];
    }

    // ─── Helper: Validate required fields ─────────────────────────────────────

    private static void validateRequest(RegistrationRequest req) {
        List<String> errors = new List<String>();

        if (String.isBlank(req.firstName))             errors.add('firstName is required.');
        if (String.isBlank(req.lastName))              errors.add('lastName is required.');
        if (String.isBlank(req.email))                 errors.add('email is required.');
        if (String.isBlank(req.password))              errors.add('password is required.');
        if (req.agreeTerms == null || !req.agreeTerms) errors.add('agreeTerms must be true.');

        if (!errors.isEmpty()) {
            throw new RegistrationException(String.join(errors, ' | '));
        }
    }

    // ─── Helper: Hash password (SHA-256 + salt) ────────────────────────────────

    private static String hashPassword(String password) {
        String salt         = generateSalt();
        Blob   passwordBlob = Blob.valueOf(salt + password);
        Blob   hashBlob     = Crypto.generateDigest('SHA-256', passwordBlob);
        return salt + ':' + EncodingUtil.base64Encode(hashBlob);
    }

    private static String generateSalt() {
        Blob randomBytes = Crypto.generateAesKey(128);
        return EncodingUtil.base64Encode(randomBytes).substring(0, 16);
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

    global class RegistrationException extends Exception {}
}