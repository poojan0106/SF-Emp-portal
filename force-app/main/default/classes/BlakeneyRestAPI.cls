/*
============================================================================
BLAKENEY CHATBOT - REST API LAYER - WITH ENHANCED LOGGING
============================================================================
*/

@RestResource(urlMapping='/blakeney/*')
global with sharing class BlakeneyRestAPI {

    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String endpoint = req.requestURI.substringAfter('/blakeney/');
        String requestBody = req.requestBody.toString();

        try {
            if (endpoint == 'chat/message') {
                return handleChatMessage(requestBody);
            } else if (endpoint == 'intent/save') {
                return handleIntentSave(requestBody);
            } else if (endpoint == 'constraints/save') {
                return handleConstraintsSave(requestBody);
            } else if (endpoint == 'career/save') {
                return handleCompleteCareerDataSave(requestBody);
            }
            res.statusCode = 404;
            return JSON.serialize(new APIResponse(false, 'Endpoint not found', null));
        } catch (Exception e) {
            res.statusCode = 500;
            return JSON.serialize(new APIResponse(false, e.getMessage(), null));
        }
    }

    @HttpGet
    global static String doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String endpoint = req.requestURI.substringAfter('/blakeney/');

        try {
            if (endpoint == 'chat/history') {
                String sessionId = req.params.get('sessionId');
                String contactId = req.params.get('contactId');
                return handleChatHistory(sessionId, contactId);
            } else if (endpoint == 'intent/get') {
                String contactId = req.params.get('contactId');
                return handleIntentGet(contactId);
            } else if (endpoint == 'intent/check') {
                String contactId = req.params.get('contactId');
                return handleIntentCheck(contactId);
            } else if (endpoint == 'constraints/get') {
                String contactId = req.params.get('contactId');
                return handleConstraintsGet(contactId);
            }
            res.statusCode = 404;
            return JSON.serialize(new APIResponse(false, 'Endpoint not found', null));
        } catch (Exception e) {
            res.statusCode = 500;
            return JSON.serialize(new APIResponse(false, e.getMessage(), null));
        }
    }

    // POST /blakeney/chat/message
    private static String handleChatMessage(String requestBody) {
        System.debug('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
        System.debug('ðŸŒ BlakeneyRestAPI.handleChatMessage');
        System.debug('   Raw Request Body: ' + requestBody);

        ChatMessageRequest cmr = (ChatMessageRequest) JSON.deserialize(requestBody, ChatMessageRequest.class);

        System.debug('   Parsed Request:');
        System.debug('      sessionId: ' + cmr.sessionId);
        System.debug('      contactId: ' + cmr.contactId);
        System.debug('      message: ' + cmr.message);
        System.debug('      contextType: ' + cmr.contextType);
        System.debug('      questionCount (from client): ' + cmr.questionCount);

        String questionCount = String.isNotBlank(cmr.questionCount) ? cmr.questionCount : '0';

        System.debug('   Using questionCount: ' + questionCount);
        System.debug('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');

        BlakeneyChatService.ChatResponse response = BlakeneyChatService.processMessage(
            cmr.sessionId,
            cmr.contactId,
            cmr.message,
            cmr.contextType,
            questionCount,
            cmr.assistantMessage,
            cmr.quickReplies,
            cmr.inputActive,
            cmr.inputType,
            cmr.inputPlaceholder,
            cmr.advanceQuestion,
            cmr.saveIntent,
            cmr.aiModel,
            cmr.totalTokens
        );

        System.debug('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');
        System.debug('ðŸŒ BlakeneyRestAPI Response:');
        System.debug('   questionCount (returning to client): ' + response.questionCount);
        System.debug('   message: ' + response.message);
        System.debug('â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•');

        ChatMessageResponse chatResp = new ChatMessageResponse();
        chatResp.sessionId = response.sessionId;
        chatResp.message = response.message;
        chatResp.quickReplies = response.quickReplies;
        chatResp.messageCount = response.messageCount;
        chatResp.questionCount = response.questionCount;
        chatResp.responseTime = response.responseTime;
        chatResp.inputActive = response.inputActive;
        chatResp.inputType = response.inputType;
        chatResp.inputPlaceholder = response.inputPlaceholder;

        return JSON.serialize(new APIResponse(true, 'Success', chatResp));
    }

    // GET /blakeney/chat/history
    private static String handleChatHistory(String sessionId, String contactId) {
        List<Chat_Interaction__c> history = BlakeneyChatService.getConversationHistory(sessionId, contactId);
        return JSON.serialize(new APIResponse(true, 'Success', history));
    }

    // POST /blakeney/intent/save (Legacy - for partial updates)
    private static String handleIntentSave(String requestBody) {
        CareerIntentRequest cir = (CareerIntentRequest) JSON.deserialize(requestBody, CareerIntentRequest.class);
        System.enqueueJob(new IntentSaveQueueable(
            cir.contactId, cir.shortTermGoal, cir.mediumTermGoal,
            cir.longTermGoal, cir.aspirationalGoal
        ));
        return JSON.serialize(new APIResponse(true, 'Intent save queued', null));
    }

    // POST /blakeney/career/save (Complete 10-field career data)
    private static String handleCompleteCareerDataSave(String requestBody) {
        CompleteCareerDataRequest ccdr = (CompleteCareerDataRequest) JSON.deserialize(requestBody, CompleteCareerDataRequest.class);

        System.debug('Received complete career data for contact: ' + ccdr.contactId);
        System.debug('Session ID: ' + ccdr.sessionId);

        // Queue all career data for async save (creates NEW record)
        System.enqueueJob(new IntentSaveQueueable(
            ccdr.contactId,
            ccdr.sessionId,
            ccdr.shortTermGoal,
            ccdr.mediumTermGoal,
            ccdr.longTermGoal,
            ccdr.aspirationalGoal,
            ccdr.workLocation,
            ccdr.remotePreference,
            ccdr.minSalary,
            ccdr.maxSalary,
            ccdr.companySize,
            ccdr.industryPreferences
        ));

        return JSON.serialize(new APIResponse(true, 'Complete career data save queued', null));
    }

    // GET /blakeney/intent/get
    private static String handleIntentGet(String contactId) {
        Career_Intent__c intent = CareerIntentService.getCareerIntent(contactId);
        return JSON.serialize(new APIResponse(true, 'Success', intent));
    }

    // GET /blakeney/intent/check - NEW: Check if user has existing data
    private static String handleIntentCheck(String contactId) {
        List<Career_Intent__c> intents = [
            SELECT Id, Contact__c, Candidate__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c, Aspirational_Goal__c,
                   Willing_to_Relocate__c, Short_Term_Remote__c, Min_Salary_Expactation__c,
                   Max_Salary_Expactation__c, Short_Term_Company_Size__c, Industry_Preferences__c,
                   Role_Title__c, Skills__c
            FROM Career_Intent__c
            WHERE Contact__c = :contactId OR Candidate__c = :contactId
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];

        if (intents.isEmpty()) {
            return JSON.serialize(new APIResponse(true, 'No existing data', null));
        }

        Career_Intent__c intent = intents[0];

        // Build summary of filled fields
        IntentCheckResponse checkResp = new IntentCheckResponse();
        checkResp.hasData = true;
        checkResp.filledFields = new List<String>();

        if (String.isNotBlank(intent.Short_Term_Goal__c)) {
            checkResp.filledFields.add('Short-term goal');
        }
        if (String.isNotBlank(intent.Medium_Term_Goal__c)) {
            checkResp.filledFields.add('Medium-term goal');
        }
        if (String.isNotBlank(intent.Long_Term_Goal__c)) {
            checkResp.filledFields.add('Long-term goal');
        }
        if (String.isNotBlank(intent.Aspirational_Goal__c)) {
            checkResp.filledFields.add('Dream job');
        }
        if (String.isNotBlank(intent.Willing_to_Relocate__c)) {
            checkResp.filledFields.add('Work location');
        }
        if (String.isNotBlank(intent.Short_Term_Remote__c)) {
            checkResp.filledFields.add('Remote preference');
        }
        if (intent.Min_Salary_Expactation__c != null) {
            checkResp.filledFields.add('Minimum salary');
        }
        if (intent.Max_Salary_Expactation__c != null) {
            checkResp.filledFields.add('Maximum salary');
        }
        if (String.isNotBlank(intent.Short_Term_Company_Size__c)) {
            checkResp.filledFields.add('Company size');
        }
        if (String.isNotBlank(intent.Industry_Preferences__c)) {
            checkResp.filledFields.add('Industries');
        }
        if (String.isNotBlank(intent.Role_Title__c)) {
            checkResp.filledFields.add('Current role');
        }
        if (String.isNotBlank(intent.Skills__c)) {
            checkResp.filledFields.add('Skills');
        }

        checkResp.nextQuestion = calculateNextQuestion(intent);

        return JSON.serialize(new APIResponse(true, 'Success', checkResp));
    }

    // Calculate next question number based on filled fields
    private static Integer calculateNextQuestion(Career_Intent__c intent) {
        if (intent == null) return 1;

        if (String.isBlank(intent.Short_Term_Goal__c)) return 1;
        if (String.isBlank(intent.Medium_Term_Goal__c)) return 2;
        if (String.isBlank(intent.Long_Term_Goal__c)) return 3;
        if (String.isBlank(intent.Aspirational_Goal__c)) return 4;
        if (String.isBlank(intent.Willing_to_Relocate__c)) return 5;
        if (String.isBlank(intent.Short_Term_Remote__c)) return 6;
        if (intent.Min_Salary_Expactation__c == null) return 7;
        if (intent.Max_Salary_Expactation__c == null) return 8;
        if (String.isBlank(intent.Short_Term_Company_Size__c)) return 9;
        if (String.isBlank(intent.Industry_Preferences__c)) return 10;
        if (String.isBlank(intent.Role_Title__c)) return 11;
        if (String.isBlank(intent.Skills__c)) return 12;

        return 13; // All complete
    }

    // POST /blakeney/constraints/save (Legacy)
    private static String handleConstraintsSave(String requestBody) {
        CareerConstraintsRequest ccr = (CareerConstraintsRequest) JSON.deserialize(requestBody, CareerConstraintsRequest.class);
        System.enqueueJob(new ConstraintsSaveQueueable(ccr));
        return JSON.serialize(new APIResponse(true, 'Constraints save queued', null));
    }

    // GET /blakeney/constraints/get
    private static String handleConstraintsGet(String contactId) {
        List<Career_Constraints__c> constraints = [
            SELECT Id, Preferred_Locations__c, Willing_to_Relocate__c,
                   Remote_Work_Requirement__c, Min_Salary__c, Max_Salary__c,
                   Compensation_Type__c, Max_Hours_Per_Week__c, Flexibility_Importance__c,
                   Travel_Willingness__c, Company_Size_Preference__c, Industry_Preferences__c,
                   Industry_Exclusions__c, Risk_Tolerance__c, Culture_Preferences__c,
                   Deal_Breakers__c
            FROM Career_Constraints__c WHERE Contact__c = :contactId LIMIT 1
        ];
        return JSON.serialize(new APIResponse(true, 'Success', constraints.isEmpty() ? null : constraints[0]));
    }

    // ========================================================================
    // WRAPPER CLASSES
    // ========================================================================

    global class APIResponse {
        public Boolean success;
        public String message;
        public Object data;
        public Long timestamp;

        public APIResponse(Boolean s, String m, Object d) {
            this.success = s;
            this.message = m;
            this.data = d;
            this.timestamp = DateTime.now().getTime();
        }
    }

    global class ChatMessageRequest {
        public String sessionId;
        public String contactId;
        public String message;
        public String contextType;
        public String questionCount;
        public String assistantMessage;
        public List<BlakeneyChatService.QuickReply> quickReplies;
        public Boolean inputActive;
        public String inputType;
        public String inputPlaceholder;
        public Boolean advanceQuestion;
        public Boolean saveIntent;
        public String aiModel;
        public Integer totalTokens;
    }

    global class ChatMessageResponse {
        public String sessionId;
        public String message;
        public List<BlakeneyChatService.QuickReply> quickReplies;
        public Integer messageCount;
        public String questionCount;
        public Long responseTime;
        public Boolean inputActive;
        public String inputType;
        public String inputPlaceholder;
    }

    global class CareerIntentRequest {
        public String contactId;
        public String shortTermGoal;
        public String mediumTermGoal;
        public String longTermGoal;
        public String aspirationalGoal;
    }

    global class CompleteCareerDataRequest {
        public String contactId;
        public String sessionId;
        public String shortTermGoal;
        public String mediumTermGoal;
        public String longTermGoal;
        public String aspirationalGoal;
        public String workLocation;
        public String remotePreference;
        public String minSalary;
        public String maxSalary;
        public String companySize;
        public String industryPreferences;
    }

    global class CareerConstraintsRequest {
        public String contactId;
        public String preferredLocations;
        public String willingToRelocate;
        public String remoteWorkRequirement;
        public Decimal minSalary;
        public Decimal maxSalary;
        public String compensationType;
        public Integer maxHoursPerWeek;
        public String flexibilityImportance;
        public String travelWillingness;
        public String companySizePreference;
        public String industryPreferences;
        public String industryExclusions;
        public String riskTolerance;
        public String culturePreferences;
        public String dealBreakers;
    }

    // NEW: Intent check response
    global class IntentCheckResponse {
        public Boolean hasData;
        public List<String> filledFields;
        public Integer nextQuestion;
    }
}
