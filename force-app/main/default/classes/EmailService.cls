/**
 * EmailService
 * Handles all email notifications
 */
public class EmailService {
    
    private static final String FROM_ADDRESS = 'noreply@rezourcer.ai';
    private static final String FROM_NAME = 'Flint - ReZourcer.ai';
    
    public static void sendInterviewRequest(String toEmail, String candidateName, String companyName, String message) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ toEmail });
        email.setSubject('Interview Request from ' + companyName);
        email.setHtmlBody(
            '<h2>Hi ' + candidateName + ',</h2>' +
            '<p>Great news! <strong>' + companyName + '</strong> would like to interview you.</p>' +
            (String.isNotBlank(message) ? '<p><em>"' + message + '"</em></p>' : '') +
            '<p><a href="https://blakeney.ai/interviews">View Interview Request</a></p>' +
            '<p>Best regards,<br/>Flint<br/>Your AI Recruitment Consultant</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendSubscriptionConfirmation(Id accountId) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Welcome to ReZourcer.ai Professional!');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>Welcome to ReZourcer.ai Professional! Your subscription is now active.</p>' +
            '<p>You now have access to:</p>' +
            '<ul>' +
            '<li>Unlimited job postings</li>' +
            '<li>Full candidate profiles</li>' +
            '<li>Interview scheduling</li>' +
            '<li>Unlimited Flint AI conversations</li>' +
            '</ul>' +
            '<p><a href="https://rezourcer.ai/dashboard">Go to Dashboard</a></p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendSubscriptionCancellation(Id accountId) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Your ReZourcer.ai subscription has been cancelled');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>Your ReZourcer.ai Professional subscription has been cancelled.</p>' +
            '<p>You will continue to have access to your current features until the end of your billing period.</p>' +
            '<p>After that, your account will revert to our Free plan with limited access.</p>' +
            '<p>Changed your mind? You can resubscribe at any time:</p>' +
            '<p><a href="https://rezourcer.ai/pricing">Resubscribe Now</a></p>' +
            '<p>We\'d love to hear your feedback on how we can improve. Feel free to reply to this email.</p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendUpgradeConfirmation(Id accountId) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Welcome to ReZourcer.ai Professional!');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>Congratulations! Your account has been upgraded to <strong>Professional</strong>.</p>' +
            '<p>You now have access to:</p>' +
            '<ul>' +
            '<li>Unlimited job postings</li>' +
            '<li>Full candidate profiles</li>' +
            '<li>Interview scheduling</li>' +
            '<li>Unlimited Flint AI conversations</li>' +
            '<li>Priority support</li>' +
            '</ul>' +
            '<p><a href="https://rezourcer.ai/dashboard">Go to Dashboard</a></p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendDowngradeNotification(Id accountId) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Your ReZourcer.ai account has been downgraded');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>Your ReZourcer.ai account has been downgraded to our <strong>Free</strong> plan.</p>' +
            '<p>With the Free plan, you\'ll have limited access to:</p>' +
            '<ul>' +
            '<li>1 active job posting</li>' +
            '<li>Basic candidate information</li>' +
            '<li>Limited Flint AI conversations</li>' +
            '</ul>' +
            '<p>Ready to upgrade again? Get full access to all features:</p>' +
            '<p><a href="https://rezourcer.ai/pricing">View Plans</a></p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendCancellationConfirmation(Id accountId) {
        Account employer = [SELECT Name FROM Account WHERE Id = :accountId];
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Subscription cancellation confirmed');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>This email confirms that your ReZourcer.ai subscription has been cancelled.</p>' +
            '<p>Your access to Professional features will continue until the end of your current billing period.</p>' +
            '<p>We\'re sorry to see you go! If there\'s anything we could have done better, we\'d love to hear from you.</p>' +
            '<p>You can reactivate your subscription at any time:</p>' +
            '<p><a href="https://rezourcer.ai/pricing">Resubscribe</a></p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendPaymentFailedNotification(Id accountId) {
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Payment Failed - Action Required');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>We were unable to process your payment for ReZourcer.ai.</p>' +
            '<p>Please update your payment method to continue enjoying Premium features.</p>' +
            '<p><a href="https://rezourcer.ai/account/billing">Update Payment Method</a></p>' +
            '<p>If you have any questions, please contact our support team.</p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendWeeklyPoolUpdate(Id accountId, String companyName, Integer newCandidates) {
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject(newCandidates + ' new candidates interested in ' + companyName);
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>Great news! <strong>' + newCandidates + ' new candidates</strong> have expressed interest in working at ' + companyName + ' this week.</p>' +
            '<p><a href="https://rezourcer.ai/talent-pools">View Your Talent Pool</a></p>' +
            '<p>Best regards,<br/>Flint<br/>Your AI Recruitment Consultant</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
    
    public static void sendTrialEndingReminder(Id accountId, Integer daysRemaining) {
        Contact primaryUser = [
            SELECT Email, FirstName FROM Contact 
            WHERE AccountId = :accountId AND Is_Employer_User__c = true 
            LIMIT 1
        ];
        
        if (primaryUser == null || String.isBlank(primaryUser.Email)) return;
        
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ primaryUser.Email });
        email.setSubject('Your trial ends in ' + daysRemaining + ' days');
        email.setHtmlBody(
            '<h2>Hi ' + primaryUser.FirstName + ',</h2>' +
            '<p>Your ReZourcer.ai Professional trial ends in <strong>' + daysRemaining + ' days</strong>.</p>' +
            '<p>Upgrade now to keep access to:</p>' +
            '<ul>' +
            '<li>Full candidate profiles</li>' +
            '<li>Unlimited job postings</li>' +
            '<li>Interview scheduling</li>' +
            '</ul>' +
            '<p><a href="https://rezourcer.ai/pricing">Upgrade Now</a></p>' +
            '<p>Best regards,<br/>The ReZourcer.ai Team</p>'
        );
        
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }
}