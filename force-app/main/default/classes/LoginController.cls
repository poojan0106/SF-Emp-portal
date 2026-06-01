/**
 * LoginController
 * REST API endpoint for user authentication
 * Authenticates against Registration_Request__c (no User record needed)
 * Endpoint: /services/apexrest/auth/*
 */
@RestResource(urlMapping='/auth/*')
global without sharing class LoginController {
    
    /**
     * Login
     * POST /services/apexrest/auth/login
     * Uses email and password from registration
     */
    @HttpPost
    global static LoginResponse login() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        try {
            String requestBody = req.requestBody.toString();
            LoginRequest loginReq = (LoginRequest) JSON.deserialize(requestBody, LoginRequest.class);
            
            // Validate request
            if (String.isBlank(loginReq.email) || String.isBlank(loginReq.password)) {
                res.statusCode = 400;
                return new LoginResponse(false, null, 'Email and password are required', null);
            }
            
            // Find completed registration by email
            List<Registration_Request__c> regRequests = [
                SELECT Id, Email__c, Password_Hash__c, Contact__c, Account__c, 
                       Full_Name__c, First_Name__c, Last_Name__c, Status__c,Registration_Type__c
                FROM Registration_Request__c 
                WHERE Email__c = :loginReq.email 
                AND Status__c = 'Completed'
                AND Contact__r.RecordType.DeveloperName = 'R_ATS_Client'
                LIMIT 1
            ];
            
            if (regRequests.isEmpty()) {
                res.statusCode = 401;
                return new LoginResponse(false, null, 'Invalid email or password', null);
            }
            
            Registration_Request__c regRequest = regRequests[0];
            
            // Verify password
            if (!verifyPassword(loginReq.password, regRequest.Password_Hash__c)) {
                res.statusCode = 401;
                return new LoginResponse(false, null, 'Invalid email or password', null);
            }
            
            // Get Account info
            Account acc = [
                SELECT Id, Name 
                FROM Account 
                WHERE Id = :regRequest.Account__c 
                LIMIT 1
            ];
            
            // Generate session token
            String sessionToken = generateSessionToken(regRequest.Id);
            
            // Get subscription info
            String subscriptionTier = SubscriptionService.getSubscriptionTier(regRequest.Account__c);
            
            res.statusCode = 200;
            return new LoginResponse(
                true,
                sessionToken,
                'Login successful',
                new UserInfo(
                    regRequest.Id,
                    regRequest.Full_Name__c,
                    regRequest.Email__c,
                    regRequest.Account__c,
                    acc.Name,
                    subscriptionTier
                )
            );
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Login error: ' + e.getMessage());
            res.statusCode = 500;
            return new LoginResponse(false, null, 'An unexpected error occurred', null);
        }
    }
    
    /**
     * Validate session
     * GET /services/apexrest/auth/validate
     */
    @HttpGet
    global static SessionValidationResponse validateSession() {
        RestRequest req = RestContext.request;
        String authHeader = req.headers.get('Authorization');
        
        if (String.isBlank(authHeader) || !authHeader.startsWith('Bearer ')) {
            return new SessionValidationResponse(false, 'Invalid or missing authorization header', null);
        }
        
        String token = authHeader.substring(7); // Remove 'Bearer '
        
        // Validate token (implement based on your session storage)
        try {
            Registration_Request__c regRequest = [
                SELECT Id, Email__c, Full_Name__c, Account__c, Account__r.Name 
                FROM Registration_Request__c 
                WHERE Id = :token 
                AND Status__c = 'Completed'
                LIMIT 1
            ];
            
            String subscriptionTier = SubscriptionService.getSubscriptionTier(regRequest.Account__c);
            
            return new SessionValidationResponse(
                true, 
                'Session valid', 
                new UserInfo(
                    regRequest.Id,
                    regRequest.Full_Name__c,
                    regRequest.Email__c,
                    regRequest.Account__c,
                    regRequest.Account__r.Name,
                    subscriptionTier
                )
            );
        } catch (Exception e) {
            return new SessionValidationResponse(false, 'Invalid or expired session', null);
        }
    }
    
    // ==================== PRIVATE METHODS ====================
    
    private static Boolean verifyPassword(String password, String storedHash) {
        try {
            // Extract salt from stored hash (format: salt:hash)
            List<String> hashParts = storedHash.split(':');
            if (hashParts.size() != 2) {
                return false;
            }
            
            String salt = hashParts[0];
            String inputHash = hashPassword(password, salt);
            
            return inputHash.equals(storedHash);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Password verification error: ' + e.getMessage());
            return false;
        }
    }
    
    private static String hashPassword(String password, String salt) {
        Blob passwordBlob = Blob.valueOf(salt + password);
        Blob hashBlob = Crypto.generateDigest('SHA-256', passwordBlob);
        return salt + ':' + EncodingUtil.base64Encode(hashBlob);
    }
    
    private static String generateSessionToken(Id registrationRequestId) {
        // Return registration request ID as token
        // This allows validateSession to retrieve user info
        return registrationRequestId;
    }
    
    // ==================== REQUEST/RESPONSE CLASSES ====================
    
    global class LoginRequest {
        public String email;
        public String password;
        public String registrationType;
    }
    
    global class LoginResponse {
        public Boolean success;
        public String sessionToken;
        public String message;
        public UserInfo user;
        
        public LoginResponse(Boolean success, String token, String message, UserInfo user) {
            this.success = success;
            this.sessionToken = token;
            this.message = message;
            this.user = user;
        }
    }
    
    global class UserInfo {
        public String userId;
        public String fullName;
        public String email;
        public String accountId;
        public String companyName;
        public String subscriptionTier;
        
        public UserInfo(String uId, String name, String email, String accId, String company, String tier) {
            this.userId = uId;
            this.fullName = name;
            this.email = email;
            this.accountId = accId;
            this.companyName = company;
            this.subscriptionTier = tier;
        }
    }
    
    global class SessionValidationResponse {
        public Boolean valid;
        public String message;
        public UserInfo user;
        
        public SessionValidationResponse(Boolean valid, String message, UserInfo user) {
            this.valid = valid;
            this.message = message;
            this.user = user;
        }
    }
}