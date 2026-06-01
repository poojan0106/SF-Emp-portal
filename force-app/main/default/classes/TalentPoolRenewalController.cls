/**
 * ═══════════════════════════════════════════════════════════════════════════
 * TalentPoolRenewalController.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: REST API endpoint for talent pool renewal operations
 * 
 * TASK COVERED: US-045-BE-035
 * 
 * ENDPOINTS:
 *   POST /api/talent-pool/renew - Renews intent (resets Intent_Added_Date__c)
 *   GET  /api/talent-pool/renew - Handles email link clicks (with token)
 *   GET  /api/talent-pool/status - Gets membership status
 * 
 * RENEWAL PROCESS:
 *   1. Candidate clicks link in reminder email
 *   2. Token is validated
 *   3. Intent_Added_Date__c is reset to today
 *   4. Reminder_Sent__c is reset to false
 *   5. Candidate stays in pool for another 12 months
 * 
 * AUTHOR: [Your Name]
 * DATE: January 2025
 * ═══════════════════════════════════════════════════════════════════════════
 */
@RestResource(urlMapping='/api/talent-pool/*')
global with sharing class TalentPoolRenewalController {
    
    // ═══════════════════════════════════════════════════════════════════════
    // HTTP GET - Handle renewal link from email
    // ═══════════════════════════════════════════════════════════════════════
    
    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        String endpoint = req.requestURI.substringAfterLast('/');
        
        try {
            if (endpoint == 'renew') {
                // Handle renewal link click from email
                String token = req.params.get('token');
                handleRenewalFromEmail(token);
            } else if (endpoint == 'status') {
                // Get membership status
                String memberId = req.params.get('memberId');
                getMembershipStatus(memberId);
            } else {
                sendResponse(400, false, 'Invalid endpoint', null);
            }
        } catch (Exception e) {
            sendResponse(500, false, 'Error: ' + e.getMessage(), null);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // HTTP POST - Renew intent programmatically
    // ═══════════════════════════════════════════════════════════════════════
    
    @HttpPost
    global static void doPost() {
        RestRequest req = RestContext.request;
        String endpoint = req.requestURI.substringAfterLast('/');
        String requestBody = req.requestBody != null ? req.requestBody.toString() : '{}';
        
        try {
            if (endpoint == 'renew') {
                handleRenewalRequest(requestBody);
            } else if (endpoint == 'opt-out') {
                handleOptOutRequest(requestBody);
            } else {
                sendResponse(400, false, 'Invalid endpoint', null);
            }
        } catch (Exception e) {
            sendResponse(500, false, 'Error: ' + e.getMessage(), null);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // TASK US-045-BE-035: Renewal Logic
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Handles renewal from email link click.
     * Validates token and renews membership.
     */
    private static void handleRenewalFromEmail(String token) {
        if (String.isBlank(token)) {
            sendResponse(400, false, 'Token is required', null);
            return;
        }
        
        // Decode and validate token
        TokenData tokenData = decodeRenewalToken(token);
        
        if (tokenData == null) {
            sendResponse(400, false, 'Invalid or malformed token', null);
            return;
        }
        
        if (tokenData.isExpired()) {
            sendResponse(410, false, 'This renewal link has expired. Please contact support.', null);
            return;
        }
        
        // Perform renewal
        RenewalResult result = renewMembership(tokenData.memberId, tokenData.contactId);
        
        if (result.success) {
            // Redirect to success page or return success response
            sendHtmlResponse(buildSuccessPage(result));
        } else {
            sendResponse(400, false, result.message, null);
        }
    }
    
    /**
     * Handles renewal request from API call (authenticated).
     */
    private static void handleRenewalRequest(String requestBody) {
        RenewalRequest renewReq;
        try {
            renewReq = (RenewalRequest) JSON.deserialize(requestBody, RenewalRequest.class);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid request format', null);
            return;
        }
        
        // Validate required fields
        if (renewReq.campaignMemberId == null && 
            (renewReq.candidateId == null || renewReq.employerId == null)) {
            sendResponse(400, false, 'Either campaignMemberId OR both candidateId and employerId are required', null);
            return;
        }
        
        // Find the campaign member
        CampaignMember member = findCampaignMember(renewReq);
        
        if (member == null) {
            sendResponse(404, false, 'Campaign membership not found', null);
            return;
        }
        
        // Perform renewal
        RenewalResult result = renewMembershipById(member.Id);
        
        if (result.success) {
            Map<String, Object> data = new Map<String, Object>{
                'memberId' => member.Id,
                'newExpiryDate' => Date.today().addDays(365),
                'employerName' => result.employerName
            };
            sendResponse(200, true, 'Interest renewed successfully', data);
        } else {
            sendResponse(400, false, result.message, null);
        }
    }
    
    /**
     * Core renewal logic - resets intent date.
     */
    private static RenewalResult renewMembership(Id memberId, Id contactId) {
        RenewalResult result = new RenewalResult();
        
        // Query the membership
        List<CampaignMember> members = [
            SELECT Id, Status, Intent_Added_Date__c, ContactId,
                   Campaign.Name, Campaign.Employer__r.Name
            FROM CampaignMember
            WHERE Id = :memberId
            AND ContactId = :contactId
            LIMIT 1
        ];
        
        if (members.isEmpty()) {
            result.success = false;
            result.message = 'Membership not found';
            return result;
        }
        
        CampaignMember member = members[0];
        
        // Check if already expired or opted out
        if (member.Status == 'Opted_Out') {
            result.success = false;
            result.message = 'You have previously opted out of this talent pool';
            return result;
        }
        
        // Perform renewal
        member.Intent_Added_Date__c = Date.today();
        member.Reminder_Sent__c = false;
        member.Reminder_Sent_Date__c = null;
        member.Renewal_Count__c = (member.Renewal_Count__c == null ? 0 : member.Renewal_Count__c) + 1;
        member.Last_Renewal_Date__c = Date.today();
        
        // If was expired, reactivate
        if (member.Status == 'Expired') {
            member.Status = 'Interested';
        }
        
        try {
            update member;
            
            result.success = true;
            result.message = 'Your interest has been renewed for another 12 months';
            result.employerName = member.Campaign.Employer__r.Name;
            result.newExpiryDate = Date.today().addDays(365);
            
        } catch (DmlException e) {
            result.success = false;
            result.message = 'Failed to renew: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Renewal by member ID only (for authenticated requests).
     */
    private static RenewalResult renewMembershipById(Id memberId) {
        RenewalResult result = new RenewalResult();
        
        List<CampaignMember> members = [
            SELECT Id, Status, Intent_Added_Date__c, ContactId, Renewal_Count__c,
                   Campaign.Name, Campaign.Employer__r.Name
            FROM CampaignMember
            WHERE Id = :memberId
            LIMIT 1
        ];
        
        if (members.isEmpty()) {
            result.success = false;
            result.message = 'Membership not found';
            return result;
        }
        
        CampaignMember member = members[0];
        
        // Perform renewal
        member.Intent_Added_Date__c = Date.today();
        member.Reminder_Sent__c = false;
        member.Reminder_Sent_Date__c = null;
        member.Renewal_Count__c = (member.Renewal_Count__c == null ? 0 : member.Renewal_Count__c) + 1;
        member.Last_Renewal_Date__c = Date.today();
        
        if (member.Status == 'Expired') {
            member.Status = 'Interested';
        }
        
        try {
            update member;
            result.success = true;
            result.message = 'Interest renewed successfully';
            result.employerName = member.Campaign.Employer__r.Name;
            result.newExpiryDate = Date.today().addDays(365);
        } catch (DmlException e) {
            result.success = false;
            result.message = 'Failed to renew: ' + e.getMessage();
        }
        
        return result;
    }
    
    /**
     * Handles opt-out request.
     */
    private static void handleOptOutRequest(String requestBody) {
        OptOutRequest optOutReq;
        try {
            optOutReq = (OptOutRequest) JSON.deserialize(requestBody, OptOutRequest.class);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid request format', null);
            return;
        }
        
        if (optOutReq.campaignMemberId == null) {
            sendResponse(400, false, 'campaignMemberId is required', null);
            return;
        }
        
        try {
            CampaignMember member = new CampaignMember(
                Id = optOutReq.campaignMemberId,
                Status = 'Opted_Out',
                Opt_Out_Date__c = Date.today(),
                Opt_Out_Reason__c = optOutReq.reason
            );
            update member;
            
            sendResponse(200, true, 'Successfully opted out', null);
        } catch (Exception e) {
            sendResponse(400, false, 'Failed to opt out: ' + e.getMessage(), null);
        }
    }
    
    /**
     * Gets membership status for a candidate.
     */
    private static void getMembershipStatus(String memberIdStr) {
        if (String.isBlank(memberIdStr)) {
            sendResponse(400, false, 'memberId parameter is required', null);
            return;
        }
        
        Id memberId;
        try {
            memberId = Id.valueOf(memberIdStr);
        } catch (Exception e) {
            sendResponse(400, false, 'Invalid memberId format', null);
            return;
        }
        
        List<CampaignMember> members = [
            SELECT Id, Status, Intent_Added_Date__c, Reminder_Sent__c,
                   Campaign.Name, Campaign.Employer__r.Name
            FROM CampaignMember
            WHERE Id = :memberId
            LIMIT 1
        ];
        
        if (members.isEmpty()) {
            sendResponse(404, false, 'Membership not found', null);
            return;
        }
        
        CampaignMember m = members[0];
        Integer daysRemaining = m.Intent_Added_Date__c != null 
            ? m.Intent_Added_Date__c.daysBetween(Date.today().addDays(365)) 
            : 365;
        
        Map<String, Object> data = new Map<String, Object>{
            'memberId' => m.Id,
            'status' => m.Status,
            'employerName' => m.Campaign.Employer__r.Name,
            'intentDate' => m.Intent_Added_Date__c,
            'expiryDate' => m.Intent_Added_Date__c != null ? m.Intent_Added_Date__c.addDays(365) : null,
            'daysRemaining' => daysRemaining,
            'reminderSent' => m.Reminder_Sent__c
        };
        
        sendResponse(200, true, 'Success', data);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════
    
    /**
     * Finds campaign member by various criteria.
     */
    private static CampaignMember findCampaignMember(RenewalRequest req) {
        if (req.campaignMemberId != null) {
            List<CampaignMember> members = [
                SELECT Id FROM CampaignMember WHERE Id = :req.campaignMemberId LIMIT 1
            ];
            return members.isEmpty() ? null : members[0];
        }
        
        // Find by candidate + employer
        List<CampaignMember> members = [
            SELECT Id 
            FROM CampaignMember 
            WHERE ContactId = :req.candidateId
            AND Campaign.Employer__c = :req.employerId
            AND Campaign.Type = 'Employer Interest Pool'
            AND Campaign.ParentId = null
            LIMIT 1
        ];
        
        return members.isEmpty() ? null : members[0];
    }
    
    /**
     * Decodes and validates renewal token.
     */
    private static TokenData decodeRenewalToken(String token) {
        try {
            String decoded = EncodingUtil.base64Decode(token).toString();
            List<String> parts = decoded.split('\\|');
            
            if (parts.size() != 3) return null;
            
            TokenData data = new TokenData();
            data.memberId = Id.valueOf(parts[0]);
            data.contactId = Id.valueOf(parts[1]);
            data.expiryTimestamp = Long.valueOf(parts[2]);
            
            return data;
        } catch (Exception e) {
            return null;
        }
    }
    
    /**
     * Builds success HTML page after renewal.
     */
    private static String buildSuccessPage(RenewalResult result) {
        return '<!DOCTYPE html>' +
            '<html><head><meta charset="utf-8"><title>Renewal Successful</title>' +
            '<style>body{font-family:Arial,sans-serif;display:flex;justify-content:center;' +
            'align-items:center;min-height:100vh;margin:0;background:#f5f5f5;}' +
            '.card{background:white;padding:40px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.1);' +
            'text-align:center;max-width:500px;}' +
            '.success-icon{font-size:60px;color:#4CAF50;margin-bottom:20px;}' +
            'h1{color:#333;margin-bottom:10px;}p{color:#666;line-height:1.6;}' +
            '.date{background:#e8f5e9;padding:10px 20px;border-radius:5px;display:inline-block;margin-top:20px;}' +
            '</style></head><body>' +
            '<div class="card">' +
            '<div class="success-icon">✓</div>' +
            '<h1>Interest Renewed!</h1>' +
            '<p>Your interest in <strong>' + result.employerName + '</strong> has been renewed.</p>' +
            '<p>You\'ll remain in their talent pool and be considered for future opportunities.</p>' +
            '<div class="date">New expiry date: <strong>' + result.newExpiryDate.format() + '</strong></div>' +
            '</div></body></html>';
    }
    
    /**
     * Sends JSON response.
     */
    private static void sendResponse(Integer statusCode, Boolean success, String message, Map<String, Object> data) {
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        
        Map<String, Object> response = new Map<String, Object>{
            'success' => success,
            'message' => message,
            'data' => data
        };
        
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(response));
    }
    
    /**
     * Sends HTML response (for email link redirects).
     */
    private static void sendHtmlResponse(String html) {
        RestContext.response.statusCode = 200;
        RestContext.response.addHeader('Content-Type', 'text/html');
        RestContext.response.responseBody = Blob.valueOf(html);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // INNER CLASSES
    // ═══════════════════════════════════════════════════════════════════════
    
    global class RenewalRequest {
        public Id campaignMemberId;
        public Id candidateId;
        public Id employerId;
    }
    
    global class OptOutRequest {
        public Id campaignMemberId;
        public String reason;
    }
    
    private class TokenData {
        public Id memberId;
        public Id contactId;
        public Long expiryTimestamp;
        
        public Boolean isExpired() {
            return DateTime.now().getTime() > expiryTimestamp;
        }
    }
    
    private class RenewalResult {
        public Boolean success = false;
        public String message;
        public String employerName;
        public Date newExpiryDate;
    }
}