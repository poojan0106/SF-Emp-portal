/**
 * RegistrationService
 * Handles the business logic for employer registration
 * Creates: Account → Contact → Subscription
 * User creation happens separately (after email verification or in separate step)
 */
public without sharing class RegistrationService {
    
    /**
     * Process a registration request
     * Creates: Account → Contact → Subscription
     */
    public static RegistrationResult processRegistration(Id registrationRequestId) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            // Get registration request
            Registration_Request__c regRequest = [
                SELECT Id, Company_Name__c, Full_Name__c, First_Name__c, Last_Name__c,
                       Email__c, Password_Hash__c, Industry__c, Company_Size__c, Status__c
                FROM Registration_Request__c
                WHERE Id = :registrationRequestId
            ];
            
            // Update status to Processing
            regRequest.Status__c = 'Processing';
            update regRequest;
            
            // Step 1: Create Account
            Account employerAccount = createEmployerAccount(regRequest);
            
            // Step 2: Create Contact
            Contact employerContact = createEmployerContact(regRequest, employerAccount.Id);
            
            // Step 3: Create Subscription (Free tier with trial)
            Employer_Subscription__c subscription = createSubscription(employerAccount.Id, regRequest.Email__c);
            
            // Step 4: Update registration request
            regRequest.Status__c = 'Completed';
            regRequest.Account__c = employerAccount.Id;
            regRequest.Contact__c = employerContact.Id;
            regRequest.Processed_Date__c = DateTime.now();
            update regRequest;
            
            // Step 5: Send welcome email
            sendWelcomeEmail(employerContact, employerAccount);
            
            // Step 6: Generate session token
            String sessionToken = generateSessionToken(employerAccount.Id);
            
            return new RegistrationResult(
                true,
                sessionToken,
                employerAccount.Id,
                employerContact.Id,
                null
            );
            
        } catch (Exception e) {
            Database.rollback(sp);
            
            // Update registration request with error
            try {
                Registration_Request__c regRequest = [
                    SELECT Id FROM Registration_Request__c 
                    WHERE Id = :registrationRequestId
                ];
                regRequest.Status__c = 'Failed';
                regRequest.Error_Message__c = e.getMessage() + '\n' + e.getStackTraceString();
                update regRequest;
            } catch (Exception updateEx) {
                System.debug(LoggingLevel.ERROR, 'Failed to update registration request: ' + updateEx.getMessage());
            }
            
            return new RegistrationResult(
                false,
                null,
                null,
                null,
                'Registration failed: ' + e.getMessage()
            );
        }
    }
    
    // ==================== PRIVATE METHODS ====================
    
    private static Account createEmployerAccount(Registration_Request__c regRequest) {
        Account acc = new Account(
            Name = regRequest.Company_Name__c,
            Industry = regRequest.Industry__c,
            Company_Size__c = regRequest.Company_Size__c,
            Is_Employer__c = true,
            Registration_Date__c = DateTime.now(),
            Registration_Source__c = 'Website',
            Profile_Completion__c = 30 // Initial completion percentage
        );
        
        insert acc;
        return acc;
    }
    
    private static Contact createEmployerContact(Registration_Request__c regRequest, Id accountId) {
        Contact con = new Contact(
            FirstName = regRequest.First_Name__c,
            LastName = regRequest.Last_Name__c,
            Email = regRequest.Email__c,
            AccountId = accountId,
            RecordTypeId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName()
                    .get('R_ATS_Client').getRecordTypeId(),
            Is_Employer_User__c = true,
            Is_Primary_Contact__c = true,
            Registration_Completed__c = true
        );
        
        insert con;
        return con;
    }
    
    private static Employer_Subscription__c createSubscription(Id accountId, String billingEmail) {
        Employer_Subscription__c sub = new Employer_Subscription__c(
            Account__c = accountId,
            Subscription_Tier__c = 'Free',
            Status__c = 'Trial',
            Billing_Email__c = billingEmail,
            Trial_Start_Date__c = Date.today(),
            Trial_End_Date__c = Date.today().addDays(14), // 14-day trial
            Features_Enabled__c = JSON.serialize(new List<String>{
                'Flint_Conversations',
                'Profile_Unlock',
                'Job_Posting'
            })
        );
        
        insert sub;
        return sub;
    }
    
    private static String generateSessionToken(Id accountId) {
        // Generate a secure session token
        // In production, use proper session management
        Blob tokenBlob = Crypto.generateAesKey(256);
        String token = EncodingUtil.base64Encode(tokenBlob);
        
        // Store token in a secure location (custom object or cache)
        // For now, return the token
        return token;
    }
    
    private static void sendWelcomeEmail(Contact con, Account acc) {
        try {
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ con.Email });
            email.setSubject('Welcome to ReZourcer.ai! 🎉');
            email.setHtmlBody(buildWelcomeEmailBody(con.FirstName, acc.Name));
            
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to send welcome email: ' + e.getMessage());
        }
    }
    
    private static String buildWelcomeEmailBody(String firstName, String companyName) {
        return '<html><body style="font-family: Arial, sans-serif;">' +
            '<div style="max-width: 600px; margin: 0 auto; padding: 20px;">' +
            '<h1 style="color: #1F4E79;">Welcome to ReZourcer.ai! 🎉</h1>' +
            '<p>Hi ' + firstName + ',</p>' +
            '<p>Thank you for registering <strong>' + companyName + '</strong> on ReZourcer.ai!</p>' +
            '<p>You\'re all set to start your AI-powered recruitment journey. Here\'s what you can do next:</p>' +
            '<ul>' +
            '<li><strong>Meet Flint</strong> - Your AI recruitment consultant is ready to help you create job postings</li>' +
            '<li><strong>Explore Talent Pools</strong> - Discover pre-interested candidates</li>' +
            '<li><strong>Complete Your Profile</strong> - Help candidates learn more about ' + companyName + '</li>' +
            '</ul>' +
            '<p>Your 14-day free trial of Professional features has started!</p>' +
            '<p style="margin-top: 30px;">' +
            '<a href="https://rezourcer.ai/dashboard" style="background-color: #1F4E79; color: white; padding: 12px 24px; text-decoration: none; border-radius: 8px;">Go to Dashboard</a>' +
            '</p>' +
            '<p style="margin-top: 30px; color: #666;">Best regards,<br/>The ReZourcer.ai Team</p>' +
            '</div>' +
            '</body></html>';
    }
    
    // ==================== RESULT CLASS ====================
    
    public class RegistrationResult {
        public Boolean success;
        public String sessionToken;
        public String accountId;
        public String contactId;
        public String userId;
        public String errorMessage;
        
        public RegistrationResult(Boolean success, String sessionToken, String accountId, 
                                   String contactId, String errorMessage) {
            this.success = success;
            this.sessionToken = sessionToken;
            this.accountId = accountId;
            this.contactId = contactId;
            this.userId = null; // User creation happens separately
            this.errorMessage = errorMessage;
        }
    }
}