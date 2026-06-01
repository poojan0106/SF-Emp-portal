/**
 * RegistrationController
 * REST API endpoint for user registration from frontend
 * Endpoint: /services/apexrest/registration/*
 * 
 * Note: User creation happens in a separate step after email verification
 */
@RestResource(urlMapping='/registration/*')
global without sharing class RegistrationController {
    
    /**
     * Register a new employer
     * POST /services/apexrest/registration
     * 
     * Creates: Account, Contact, Subscription
     * User creation happens after email verification
     */
    @HttpPost
    global static RegistrationResponse registerEmployer() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            // Parse request body
            String requestBody = req.requestBody.toString();
            RegistrationRequest regRequest = (RegistrationRequest) JSON.deserialize(
                requestBody, 
                RegistrationRequest.class
            );
            
            // Validate request
            List<String> validationErrors = validateRequest(regRequest);
            if (!validationErrors.isEmpty()) {
                res.statusCode = 400;
                return new RegistrationResponse(false, null, String.join(validationErrors, '; '));
            }
            
            // Check for duplicate email
            if (isDuplicateEmail(regRequest.email)) {
                res.statusCode = 409; // Conflict
                return new RegistrationResponse(false, null, 'An account with this email already exists. Please sign in.');
            }
            
            // Create Registration Request record
            Registration_Request__c regRecord = createRegistrationRequest(regRequest);
            
            // Process registration (create Account, Contact, Subscription - NOT User)
            RegistrationService.RegistrationResult result = RegistrationService.processRegistration(regRecord.Id);
            
            if (result.success) {
                res.statusCode = 201; // Created
                return new RegistrationResponse(
                    true, 
                    result.sessionToken,
                    'Registration successful! Check your email to verify your account.',
                    result.accountId,
                    result.contactId
                );
            } else {
                res.statusCode = 500;
                return new RegistrationResponse(false, null, result.errorMessage);
            }
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Registration error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            res.statusCode = 500;
            return new RegistrationResponse(false, null, 'An unexpected error occurred. Please try again.');
        }
    }
    
    /**
     * Check if email exists
     * GET /services/apexrest/registration/check-email?email=xxx
     */
    @HttpGet
    global static EmailCheckResponse checkEmail() {
        RestRequest req = RestContext.request;
        String email = req.params.get('email');
        
        if (String.isBlank(email)) {
            return new EmailCheckResponse(false, 'Email is required');
        }
        
        Boolean exists = isDuplicateEmail(email);
        return new EmailCheckResponse(true, exists ? 'Email already registered' : 'Email available', exists);
    }
    
    // ==================== PRIVATE METHODS ====================
    
    private static List<String> validateRequest(RegistrationRequest req) {
        List<String> errors = new List<String>();
        
        if (String.isBlank(req.companyName)) {
            errors.add('Company name is required');
        }
        if (String.isBlank(req.fullName)) {
            errors.add('Full name is required');
        }
        if (String.isBlank(req.email)) {
            errors.add('Email is required');
        } else if (!isValidEmail(req.email)) {
            errors.add('Invalid email format');
        }
        if (String.isBlank(req.password)) {
            errors.add('Password is required');
        } else if (!isValidPassword(req.password)) {
            errors.add('Password must be at least 8 characters with uppercase, number, and special character');
        }
        if (String.isBlank(req.industry)) {
            errors.add('Industry is required');
        }
        if (String.isBlank(req.companySize)) {
            errors.add('Company size is required');
        }
        if (!req.agreeTerms) {
            errors.add('You must agree to the Terms and Conditions');
        }
        
        return errors;
    }
    
    private static Boolean isValidEmail(String email) {
        String emailRegex = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
        Pattern emailPattern = Pattern.compile(emailRegex);
        Matcher emailMatcher = emailPattern.matcher(email);
        return emailMatcher.matches();
    }
    
    private static Boolean isValidPassword(String password) {
        if (password.length() < 8) return false;
        if (!Pattern.matches('.*[A-Z].*', password)) return false;
        if (!Pattern.matches('.*[0-9].*', password)) return false;
        if (!Pattern.matches('.*[!@#$%^&*].*', password)) return false;
        return true;
    }
    
    private static Boolean isDuplicateEmail(String email) {
        // Check Contact
        List<Contact> existingContacts = [
            SELECT Id FROM Contact 
            WHERE Email = :email 
            LIMIT 1
        ];
        if (!existingContacts.isEmpty()) return true;
        
        // Check User
        List<User> existingUsers = [
            SELECT Id FROM User 
            WHERE Email = :email OR Username = :email 
            LIMIT 1
        ];
        if (!existingUsers.isEmpty()) return true;
        
        // Check pending registrations
        List<Registration_Request__c> pendingRegs = [
            SELECT Id FROM Registration_Request__c 
            WHERE Email__c = :email 
            AND Status__c IN ('Pending', 'Processing')
            LIMIT 1
        ];
        return !pendingRegs.isEmpty();
    }
    
    private static Registration_Request__c createRegistrationRequest(RegistrationRequest req) {
        // Parse full name
        List<String> nameParts = req.fullName.trim().split(' ', 2);
        String firstName = nameParts[0];
        String lastName = nameParts.size() > 1 ? nameParts[1] : nameParts[0];
        
        Registration_Request__c regRecord = new Registration_Request__c(
            Company_Name__c = req.companyName,
            Full_Name__c = req.fullName,
            First_Name__c = firstName,
            Last_Name__c = lastName,
            Email__c = req.email,
            Password_Hash__c = hashPassword(req.password),
            Industry__c = req.industry,
            Company_Size__c = req.companySize,
            Status__c = 'Pending',
            Agreed_To_Terms__c = req.agreeTerms,
            Terms_Agreed_Date__c = DateTime.now(),
            IP_Address__c = RestContext.request.headers.get('X-Forwarded-For')
        );
        
        insert regRecord;
        return regRecord;
    }
    
    private static String hashPassword(String password) {
        // Use SHA-256 with salt for password hashing
        String salt = generateSalt();
        Blob passwordBlob = Blob.valueOf(salt + password);
        Blob hashBlob = Crypto.generateDigest('SHA-256', passwordBlob);
        return salt + ':' + EncodingUtil.base64Encode(hashBlob);
    }
    
    private static String generateSalt() {
        Blob randomBytes = Crypto.generateAesKey(128);
        return EncodingUtil.base64Encode(randomBytes).substring(0, 16);
    }
    
    // ==================== REQUEST/RESPONSE CLASSES ====================
    
    global class RegistrationRequest {
        public String companyName;
        public String fullName;
        public String email;
        public String password;
        public String industry;
        public String companySize;
        public Boolean agreeTerms;
    }
    
    global class RegistrationResponse {
        public Boolean success;
        public String sessionToken;
        public String message;
        public String accountId;
        public String contactId;
        
        public RegistrationResponse(Boolean success, String token, String message) {
            this.success = success;
            this.sessionToken = token;
            this.message = message;
        }
        
        public RegistrationResponse(Boolean success, String token, String message, 
                                     String accountId, String contactId) {
            this.success = success;
            this.sessionToken = token;
            this.message = message;
            this.accountId = accountId;
            this.contactId = contactId;
        }
    }
    
    global class EmailCheckResponse {
        public Boolean success;
        public String message;
        public Boolean exists;
        
        public EmailCheckResponse(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
        
        public EmailCheckResponse(Boolean success, String message, Boolean exists) {
            this.success = success;
            this.message = message;
            this.exists = exists;
        }
    }
}