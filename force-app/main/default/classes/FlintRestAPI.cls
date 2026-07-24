/**
 * FlintRestAPI - COMPLETE FIXED VERSION
 * Entry point for Flint AI chat REST endpoints
 * Endpoint: /services/apexrest/flint/*
 */
@RestResource(urlMapping='/flint/*')
global with sharing class FlintRestAPI {
    
    @HttpPost
    global static String doPost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String endpoint = req.requestURI.substringAfter('/flint/');
        String requestBody = req.requestBody.toString();
        
        System.debug('═══════════════════════════════════════════════════════');
        System.debug('🌐 FlintRestAPI.doPost');
        System.debug('   Endpoint: ' + endpoint);
        System.debug('═══════════════════════════════════════════════════════');
        
        try {
            if (endpoint == 'chat/start') {
                return handleChatStart(requestBody, res);
            } else if (endpoint == 'chat/message') {
                return handleChatMessage(requestBody, res);
            } else if (endpoint == 'conversation/complete') {
                return handleCompleteConversation(requestBody, res);
            }
            
            res.statusCode = 404;
            return JSON.serialize(new APIResponse(false, 'Endpoint not found', null));
        } catch (Exception e) {
            res.statusCode = 500;
            System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage() + '\n' + e.getStackTraceString());
            return JSON.serialize(new APIResponse(false, 'Server error: ' + e.getMessage(), null));
        }
    }
    
    @HttpGet
    global static String doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String endpoint = req.requestURI.substringAfter('/flint/');
        
        System.debug('═══════════════════════════════════════════════════════');
        System.debug('🌐 FlintRestAPI.doGet');
        System.debug('   Endpoint: ' + endpoint);
        System.debug('═══════════════════════════════════════════════════════');
        
        try {
            if (endpoint == 'chat/history') {
                String interactionId = req.params.get('interactionId');
                return handleChatHistory(interactionId, res);
            } else if (endpoint == 'conversation/get') {
                String interactionId = req.params.get('interactionId');
                return handleGetConversation(interactionId, res);
            }
            
            res.statusCode = 404;
            return JSON.serialize(new APIResponse(false, 'Endpoint not found', null));
        } catch (Exception e) {
            res.statusCode = 500;
            System.debug(LoggingLevel.ERROR, 'Error: ' + e.getMessage());
            return JSON.serialize(new APIResponse(false, 'Server error: ' + e.getMessage(), null));
        }
    }
    
    // ========================================================================
    // ENDPOINT HANDLERS
    // ========================================================================
    
    /**
     * POST /flint/chat/start
     * Starts a new conversation
     */
    private static String handleChatStart(String requestBody, RestResponse res) {
        System.debug('🔧 handleChatStart');
        
        // Deserialize request
        ChatStartRequest req;
        try {
            req = (ChatStartRequest) JSON.deserialize(requestBody, ChatStartRequest.class);
        } catch (Exception e) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Invalid request body', null));
        }
        
        // Validate required fields
        if (String.isBlank(req.accountId)) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Account ID is required', null));
        }
        
        if (String.isBlank(req.conversationType)) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Conversation type is required', null));
        }
        
        System.debug('   Account ID: ' + req.accountId);
        System.debug('   Conversation Type: ' + req.conversationType);
        
        // Get contact for this account
        Id contactId = null;
        try {
            List<Contact> contacts = [
                SELECT Id FROM Contact 
                WHERE AccountId = :req.accountId 
                AND Is_Employer_User__c = true
                LIMIT 1
            ];
            
            if (!contacts.isEmpty()) {
                contactId = contacts[0].Id;
                System.debug('   Contact ID: ' + contactId);
            } else {
                System.debug(LoggingLevel.WARN, '   No employer contact found for account');
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Error finding contact: ' + e.getMessage());
        }
        
        // Create interaction record
        Chat_Interaction__c interaction = new Chat_Interaction__c(
            Account__c = req.accountId,
            Conversation_Type__c = req.conversationType,
            Status__c = 'Active',
            Started_At__c = DateTime.now(),
            Session_ID__c = generateSessionId(),
            AI_Model__c = 'claude-sonnet-4-20250514',
            Contact__c = contactId,
            Message_Count__c = 0
        );
        
        try {
            insert interaction;
        } catch (Exception e) {
            res.statusCode = 500;
            System.debug(LoggingLevel.ERROR, 'Failed to insert interaction: ' + e.getMessage());
            return JSON.serialize(new APIResponse(false, 'Failed to create conversation', null));
        }
        
        // Queue initial greeting message with 9 parameters
        String greeting = FlintJobSequence.getQuestion(0);
        System.enqueueJob(new FlintDMLQueueable(
            interaction.Id,
            '',
            greeting,
            0,
            0,
            null,
            interaction.Session_ID__c,
            contactId,
            interaction.Started_At__c
        ));
        
        // Build response
        ChatStartResponse response = new ChatStartResponse();
        response.sessionId = interaction.Session_ID__c;
        response.interactionId = interaction.Id;
        response.message = greeting;
        response.questionCount = '0';
        response.inputType = FlintJobSequence.getInputType(0);
        response.quickReplies = FlintJobSequence.getQuickReplies(0);
        
        System.debug('✅ Conversation started: ' + interaction.Id);
        
        res.statusCode = 201;
        return JSON.serialize(new APIResponse(true, 'Conversation started', response));
    }
    
    /**
     * POST /flint/chat/message
     * Processes a message and returns AI response
     */
    private static String handleChatMessage(String requestBody, RestResponse res) {
        System.debug('🔧 handleChatMessage');
        
        ChatMessageRequest cmr;
        try {
            cmr = (ChatMessageRequest) JSON.deserialize(requestBody, ChatMessageRequest.class);
        } catch (Exception e) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Invalid request body', null));
        }
        
        // Validate required fields
        if (String.isBlank(cmr.interactionId)) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Interaction ID is required', null));
        }
        
        if (String.isBlank(cmr.message)) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Message is required', null));
        }
        
        System.debug('   Interaction ID: ' + cmr.interactionId);
        System.debug('   Question Count: ' + cmr.questionCount);
        
        // Get conversation details
        List<Chat_Interaction__c> interactions;
        try {
            interactions = [
                SELECT Id, Account__c, Conversation_Type__c
                FROM Chat_Interaction__c 
                WHERE Id = :cmr.interactionId
                LIMIT 1
            ];
        } catch (Exception e) {
            res.statusCode = 500;
            return JSON.serialize(new APIResponse(false, 'Failed to retrieve conversation', null));
        }
        
        if (interactions.isEmpty()) {
            res.statusCode = 404;
            return JSON.serialize(new APIResponse(false, 'Conversation not found', null));
        }
        
        Chat_Interaction__c interaction = interactions[0];
        
        // Process message (returns immediately, DML queued)
        FlintChatService.FlintResponse response = FlintChatService.processMessage(
            cmr.interactionId,
            cmr.message,
            interaction.Conversation_Type__c,
            cmr.questionCount
        );
        
        ChatMessageResponse chatResp = new ChatMessageResponse();
        chatResp.interactionId = response.interactionId;
        chatResp.message = response.message;
        chatResp.inputType = response.inputType;
        chatResp.quickReplies = response.quickReplies;
        chatResp.messageCount = response.messageCount;
        chatResp.questionCount = response.questionCount;
        chatResp.responseTime = response.responseTime;
        
        System.debug('✅ Message processed');
        System.debug('   Next question: ' + response.questionCount);
        
        res.statusCode = 200;
        return JSON.serialize(new APIResponse(true, 'Message processed', chatResp));
    }
    
    /**
     * GET /flint/chat/history
     * Retrieves chat history
     */
    private static String handleChatHistory(String interactionId, RestResponse res) {
        System.debug('🔧 handleChatHistory: ' + interactionId);
        
        if (String.isBlank(interactionId)) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Interaction ID is required', null));
        }
        
        List<Chat_Interaction__c> history;
        try {
            history = [
                SELECT Id, Message_Type__c, Message_Content__c, Timestamp__c, 
                       Total_Tokens__c, Response_Time_ms__c
                FROM Chat_Interaction__c
                WHERE Chat_Interaction__c = :interactionId
                ORDER BY Timestamp__c ASC
                LIMIT 100
            ];
        } catch (Exception e) {
            res.statusCode = 500;
            return JSON.serialize(new APIResponse(false, 'Failed to retrieve history', null));
        }
        
        System.debug('✅ Retrieved ' + history.size() + ' messages');
        
        res.statusCode = 200;
        return JSON.serialize(new APIResponse(true, 'Success', history));
    }
    
    /**
     * POST /flint/conversation/complete
     * Completes a conversation and creates job if applicable
     * ✅ FIXED: Now retrieves extracted job details from stored Extracted_Job_Data__c field
     */
    /**
         * Modified: Extract only at completion, not per message
         */
    
        private static String handleCompleteConversation(String requestBody, RestResponse res) {
            System.debug('🔧 handleCompleteConversation');
            
            CompleteConversationRequest req;
            try {
                req = (CompleteConversationRequest) JSON.deserialize(
                    requestBody, CompleteConversationRequest.class
                );
            } catch (Exception e) {
                res.statusCode = 400;
                return JSON.serialize(new APIResponse(false, 'Invalid request body', null));
            }
            
            if (String.isBlank(req.interactionId)) {
                res.statusCode = 400;
                return JSON.serialize(new APIResponse(false, 'Interaction ID is required', null));
            }
            
            List<Chat_Interaction__c> interactions;
            try {
                interactions = [
                    SELECT Id, Account__c, Conversation_Type__c
                    FROM Chat_Interaction__c 
                    WHERE Id = :req.interactionId
                    LIMIT 1
                ];
            } catch (Exception e) {
                res.statusCode = 500;
                return JSON.serialize(new APIResponse(false, 'Failed to retrieve conversation', null));
            }
            
            if (interactions.isEmpty()) {
                res.statusCode = 404;
                return JSON.serialize(new APIResponse(false, 'Conversation not found', null));
            }
            
            Chat_Interaction__c interaction = interactions[0];
            Id campaignId = null;
            
            // ✅ FIXED: Extract at completion time with ALL messages
            if (interaction.Conversation_Type__c == 'Job_Intake') {
                System.debug('📋 Extracting job details from complete conversation...');
                
                // Get ALL messages from this interaction
                List<Chat_Interaction__c> allMessages = [
                    SELECT Message_Type__c, Message_Content__c
                    FROM Chat_Interaction__c
                    WHERE Chat_Interaction__c = :req.interactionId
                    ORDER BY Timestamp__c ASC
                ];
                
                if (!allMessages.isEmpty()) {
                    // Build complete message history
                    List<Map<String, String>> messageHistory = new List<Map<String, String>>();
                    for (Chat_Interaction__c msg : allMessages) {
                        messageHistory.add(new Map<String, String>{
                            'role' => msg.Message_Type__c.toLowerCase(),
                            'content' => msg.Message_Content__c
                        });
                    }
                    
                    // Extract job details ONE TIME with all messages
                    Map<String, Object> jobDetails = ClaudeAPIService.extractJobDetailsFromMessages(messageHistory);
                    if (jobDetails == null || jobDetails.isEmpty() || !jobDetails.containsKey('job_title')) {
                        jobDetails = buildJobDetailsFromScriptedAnswers(allMessages);
                    }
                    
                    System.debug('📋 Extracted job details: ' + jobDetails.keySet());
                    
                    if (jobDetails != null && !jobDetails.isEmpty()) {
                        try {
                            campaignId = JobCampaignService.createFromFlint(interaction.Account__c, jobDetails);
                            interaction.Related_Campaign__c = campaignId;
                            interaction.Outcome__c = 'Job_Created';
                            System.debug('✅ Campaign created: ' + campaignId);
                        } catch (Exception e) {
                            System.debug(LoggingLevel.ERROR, 'Failed to create job: ' + e.getMessage());
                  
                        }
                    } else {
                        System.debug(LoggingLevel.WARN, 'No job details found');
                        interaction.Outcome__c = 'No_Action';
                    }
                }
            } else {
                interaction.Outcome__c = 'No_Action';
            }
            
            interaction.Status__c = 'Completed';
            interaction.Ended_At__c = DateTime.now();
            
            try {
                update interaction;
            } catch (Exception e) {
                res.statusCode = 500;
                return JSON.serialize(new APIResponse(false, 'Failed to complete conversation', null));
            }
            
            // Cleanup session
            FlintChatService.endSession(req.interactionId);
            
            CompleteConversationResponse response = new CompleteConversationResponse();
            response.campaignId = campaignId;
            response.interactionId = req.interactionId;
            response.status = 'Completed';
            
            System.debug('✅ Conversation completed');
            
            res.statusCode = 200;
            return JSON.serialize(new APIResponse(true, 'Conversation completed', response));
        }
    
    /**
     * GET /flint/conversation/get
     * Retrieves conversation details
     */
    private static String handleGetConversation(String interactionId, RestResponse res) {
        System.debug('🔧 handleGetConversation: ' + interactionId);
        
        if (String.isBlank(interactionId)) {
            res.statusCode = 400;
            return JSON.serialize(new APIResponse(false, 'Interaction ID is required', null));
        }
        
        List<Chat_Interaction__c> interactions;
        try {
            interactions = [
                SELECT Id, Account__c, Conversation_Type__c, Status__c, 
                       Started_At__c, Ended_At__c, Outcome__c, Related_Campaign__c,
                       Message_Count__c, Total_Tokens__c
                FROM Chat_Interaction__c 
                WHERE Id = :interactionId
                LIMIT 1
            ];
        } catch (Exception e) {
            res.statusCode = 500;
            return JSON.serialize(new APIResponse(false, 'Failed to retrieve conversation', null));
        }
        
        if (interactions.isEmpty()) {
            res.statusCode = 404;
            return JSON.serialize(new APIResponse(false, 'Conversation not found', null));
        }
        
        System.debug('✅ Retrieved conversation');
        
        res.statusCode = 200;
        return JSON.serialize(new APIResponse(true, 'Success', interactions[0]));
    }
    
    // ========================================================================
    // HELPER METHODS
    // ========================================================================
    
    /**
     * Extract job details from conversation messages
     * Retrieves stored extracted data from the most recent assistant message
     * ✅ This is the KEY method that makes JobCampaignService work
     */
    private static Map<String,Object> extractJobDetailsFromConversation(Id interactionId) {
        System.debug('🔍 Extracting job details from conversation: ' + interactionId);
        
               try {
            // Query all assistant messages (don't filter on Extracted_Job_Data__c as it may not exist yet)
            List<Chat_Interaction__c> messages = [
                SELECT Id, Extracted_Job_Data__c, Timestamp__c
                FROM Chat_Interaction__c
                WHERE Chat_Interaction__c = :interactionId
                AND Message_Type__c = 'Assistant'
                ORDER BY Timestamp__c DESC
                LIMIT 10
            ];
            
            // Loop through messages to find one with extracted data
            for (Chat_Interaction__c msg : messages) {
                if (String.isNotBlank(msg.Extracted_Job_Data__c)) {
                    String extractedDataJson = msg.Extracted_Job_Data__c;
                    System.debug('📊 Raw extracted data: ' + extractedDataJson);
                    
                    Map<String,Object> jobDetails = (Map<String,Object>) JSON.deserializeUntyped(extractedDataJson);
                    System.debug('✅ Parsed job details with keys: ' + jobDetails.keySet());
                    
                    return jobDetails;
                }
            }
            
            System.debug(LoggingLevel.WARN, 'No extracted data found in conversation');
            return new Map<String,Object>();
            
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error extracting job details: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return new Map<String,Object>();
        }
    }
    
    private static Map<String, Object> buildJobDetailsFromScriptedAnswers(List<Chat_Interaction__c> messages) {
        List<String> answers = new List<String>();
        for (Chat_Interaction__c msg : messages) {
            if (msg.Message_Type__c == 'User' && String.isNotBlank(msg.Message_Content__c)) {
                answers.add(msg.Message_Content__c.trim());
            }
        }

        Map<String, Object> jobDetails = new Map<String, Object>();
        if (answers.isEmpty()) return jobDetails;

        String title = answers[0];
        jobDetails.put('job_title', String.isBlank(title) ? 'New Position' : title.trim());

        String seniority = answers.size() > 1 ? findSeniority(answers[1]) : null;
        if (String.isNotBlank(seniority)) jobDetails.put('seniority_level', seniority);

        if (answers.size() > 2) jobDetails.put('must_have_skills', splitCsv(answers[2]));
        if (answers.size() > 3) jobDetails.put('nice_to_have_skills', splitCsv(answers[3]));
        if (answers.size() > 4) {
            Map<String, Decimal> salary = parseSalaryRange(answers[4]);
            if (salary.containsKey('min')) jobDetails.put('salary_min', salary.get('min'));
            if (salary.containsKey('max')) jobDetails.put('salary_max', salary.get('max'));
        }
        if (answers.size() > 5) {
            Integer openings = parseOpenings(answers[5]);
            if (openings != null) jobDetails.put('job_openings', openings);
        }
        if (answers.size() > 6) {
            jobDetails.put('timeline_days', parseTimelineDays(answers[6]));
            jobDetails.put('urgency', parseUrgency(answers[6]));
        }
        if (answers.size() > 7) jobDetails.put('Employment_Type', normalizeEmploymentType(answers[7]));
        if (answers.size() > 8) jobDetails.put('culture_notes', answers[8]);
        if (answers.size() > 9) jobDetails.put('location', answers[9]);

        return jobDetails;
    }

    private static String findSeniority(String value) {
        String lower = String.isBlank(value) ? '' : value.toLowerCase();
        if (lower.contains('executive')) return 'Executive';
        if (lower.contains('lead')) return 'Lead';
        if (lower.contains('senior')) return 'Senior';
        if (lower.contains('junior')) return 'Junior';
        if (lower.contains('mid')) return 'Mid';
        return null;
    }

    private static List<Object> splitCsv(String value) {
        List<Object> output = new List<Object>();
        if (String.isBlank(value)) return output;
        for (String part : value.split('[,;\\n]')) {
            String item = part.trim();
            if (String.isNotBlank(item)) output.add(item);
        }
        return output;
    }

    private static Map<String, Decimal> parseSalaryRange(String value) {
        Map<String, Decimal> salary = new Map<String, Decimal>();
        if (String.isBlank(value)) return salary;
        Matcher matcher = Pattern.compile('(\\d+[\\d,]*)').matcher(value);
        List<Decimal> values = new List<Decimal>();
        while (matcher.find()) {
            String raw = matcher.group(1).replace(',', '');
            Decimal parsed = Decimal.valueOf(raw);
            if (value.toLowerCase().contains('k') && parsed < 1000) parsed *= 1000;
            values.add(parsed);
        }
        if (!values.isEmpty()) salary.put('min', values[0]);
        if (values.size() > 1) salary.put('max', values[1]);
        return salary;
    }

    private static Integer parseOpenings(String value) {
        if (String.isBlank(value)) return null;
        String trimmed = value.trim();
        if (!Pattern.compile('^\\d+$').matcher(trimmed).matches()) return null;
        return Integer.valueOf(trimmed);
    }

    private static Integer parseTimelineDays(String value) {
        if (String.isBlank(value)) return null;
        String lower = value.toLowerCase();
        if (lower.contains('immediate')) return 14;
        if (lower.contains('moderate')) return 30;
        if (lower.contains('flexible')) return 45;
        Matcher matcher = Pattern.compile('(\\d+)').matcher(lower);
        if (matcher.find()) return Integer.valueOf(matcher.group(1));
        return null;
    }

    private static String parseUrgency(String value) {
        if (String.isBlank(value)) return null;
        String lower = value.toLowerCase();
        if (lower.contains('immediate') || lower.contains('0-2')) return 'Critical';
        if (lower.contains('moderate') || lower.contains('2-4')) return 'Medium';
        if (lower.contains('flexible') || lower.contains('1+')) return 'Low';
        return null;
    }

    private static String normalizeEmploymentType(String value) {
        String lower = String.isBlank(value) ? '' : value.toLowerCase();
        if (lower.contains('contract')) return 'Contract';
        if (lower.contains('temp')) return 'Temporary';
        return 'Permanent';
    }

    private static String generateSessionId() {
        return 'FLINT-' + String.valueOf(DateTime.now().getTime()) + '-' + 
               EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
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
    
    global class ChatStartRequest {
        public String accountId;
        public String conversationType;
    }
    
    global class ChatStartResponse {
        public String sessionId;
        public String interactionId;
        public String message;
        public String questionCount;
        public String inputType;
        public List<String> quickReplies;
    }
    
    global class ChatMessageRequest {
        public String interactionId;
        public String message;
        public String questionCount;
    }
    
    global class ChatMessageResponse {
        public String interactionId;
        public String message;
        public String inputType;
        public List<String> quickReplies;
        public Integer messageCount;
        public String questionCount;
        public Long responseTime;
    }
    
    global class CompleteConversationRequest {
        public String interactionId;
        public Map<String, Object> jobDetails;
    }
    
    global class CompleteConversationResponse {
        public String interactionId;
        public String campaignId;
        public String status;
    }
}
