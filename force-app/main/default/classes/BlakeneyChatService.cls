/*
----------------------------------------------------------------------------
BlakeneyChatService.cls - FIXED INCREMENT LOGIC
Session management - questionCount only increments on VALID responses
CRITICAL FIX: Removed double-increment bug
----------------------------------------------------------------------------
*/
public with sharing class BlakeneyChatService {
    
    // Session cache for active conversations (in-memory, no DML)
    private static Map<String, ChatSession> activeSessions = new Map<String, ChatSession>();
    
    public static ChatResponse processMessage(String sessionId, String contactId, 
                                              String userMessage, String contextType, String currentQuestionCount) {
        
        System.debug('═══════════════════════════════════════════════════════');
        System.debug('📥 Processing message');
        System.debug('   Session ID: ' + sessionId);
        System.debug('   Question Count (from client): ' + currentQuestionCount);
        System.debug('   User Message: ' + userMessage);
        System.debug('═══════════════════════════════════════════════════════');
        
        // Get or create session (in-memory)
        ChatSession session = getOrCreateSession(sessionId, contactId);
        
        // CRITICAL: Use question count from CLIENT
        if (currentQuestionCount != null) {
            session.questionCount = currentQuestionCount;
            System.debug('📊 Using client questionCount: ' + currentQuestionCount);
        }
        
        // Handle resume decision responses
        if (userMessage.equalsIgnoreCase('update') || userMessage.toLowerCase().contains('update information')) {
            System.debug('🔄 User chose UPDATE - resetting to question 1');
            session.questionCount = '1';
            session.isResumeScenario = false;
        } else if (userMessage.equalsIgnoreCase('continue') || userMessage.toLowerCase().contains('continue where i left off')) {
            System.debug('▶️ User chose CONTINUE - keeping questionCount: ' + session.questionCount);
            session.isResumeScenario = false;
            session.needsDataCopy = true;
        }
        
        // Build Context (SOQL only)
        ChatContext ctx = buildChatContext(contactId, session);
        
        // Call Claude API with CURRENT questionCount
        Long startTime = System.currentTimeMillis();
        ClaudeAIService.AIResponse aiResponse = ClaudeAIService.generateResponse(
            userMessage, ctx, contextType, session.questionCount
        );
        Long responseTime = System.currentTimeMillis() - startTime;
        
        // Queue ALL DML Operations
        System.enqueueJob(new ChatDMLQueueable(
            session.sessionId,
            contactId,
            userMessage,
            aiResponse.content,
            contextType,
            aiResponse.totalTokens,
            responseTime,
            aiResponse.model,
            session.needsDataCopy
        ));
        
        // Update session tracking
        session.messageCount++;
        session.lastActivity = DateTime.now();
        
        // CRITICAL FIX: Calculate NEXT questionCount to return to client
        // Client will send this back on next request
        String nextQuestionCount = String.valueOf(
            Integer.valueOf(session.questionCount) + 1
        );
        
        System.debug('📤 Returning response');
        System.debug('   Current questionCount: ' + session.questionCount);
        System.debug('   Next questionCount (for client): ' + nextQuestionCount);
        System.debug('═══════════════════════════════════════════════════════');
        
        return new ChatResponse(
            session.sessionId,
            aiResponse.content,
            aiResponse.quickReplies,
            session.messageCount,
            nextQuestionCount,  // Return NEXT count for client to use
            aiResponse.inputActive,
            aiResponse.inputType,
            aiResponse.inputPlaceholder
        );
    }
    
    // Get latest career intent for contact
    private static Career_Intent__c getLatestCareerIntent(String contactId) {
        List<Career_Intent__c> intents = [
            SELECT Id, Contact__c, Session_ID__c,
                   Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c, Aspirational_Goal__c,
                   Willing_to_Relocate__c, Short_Term_Remote__c, Min_Salary_Expactation__c,
                   Max_Salary_Expactation__c, Short_Term_Company_Size__c, Industry_Preferences__c,
                   Role_Title__c, Last_Check_In__c
            FROM Career_Intent__c 
            WHERE Contact__c = :contactId 
            ORDER BY CreatedDate DESC 
            LIMIT 1
        ];
        
        return intents.isEmpty() ? null : intents[0];
    }
    
    // Check if intent has any data filled
    private static Boolean hasPartialData(Career_Intent__c intent) {
        if (intent == null) return false;
        
        return String.isNotBlank(intent.Short_Term_Goal__c) ||
               String.isNotBlank(intent.Medium_Term_Goal__c) ||
               String.isNotBlank(intent.Long_Term_Goal__c) ||
               String.isNotBlank(intent.Aspirational_Goal__c) ||
               String.isNotBlank(intent.Willing_to_Relocate__c) ||
               String.isNotBlank(intent.Short_Term_Remote__c) ||
               intent.Min_Salary_Expactation__c != null ||
               intent.Max_Salary_Expactation__c != null ||
               String.isNotBlank(intent.Short_Term_Company_Size__c) ||
               String.isNotBlank(intent.Industry_Preferences__c) ||
               String.isNotBlank(intent.Role_Title__c);
    }
    
    // Create resume prompt response
    private static ChatResponse createResumePrompt(ChatSession session, Career_Intent__c intent) {
        String message = 'Welcome back! I see you\'ve already provided some information:\n\n';
        
        if (String.isNotBlank(intent.Short_Term_Goal__c)) {
            message += '✓ Short-term goal\n';
        }
        if (String.isNotBlank(intent.Medium_Term_Goal__c)) {
            message += '✓ Medium-term goal\n';
        }
        if (String.isNotBlank(intent.Long_Term_Goal__c)) {
            message += '✓ Long-term goal\n';
        }
        if (String.isNotBlank(intent.Aspirational_Goal__c)) {
            message += '✓ Dream job\n';
        }
        if (String.isNotBlank(intent.Willing_to_Relocate__c)) {
            message += '✓ Work location preference\n';
        }
        if (String.isNotBlank(intent.Short_Term_Remote__c)) {
            message += '✓ Remote work preference\n';
        }
        if (intent.Min_Salary_Expactation__c != null) {
            message += '✓ Minimum salary\n';
        }
        if (intent.Max_Salary_Expactation__c != null) {
            message += '✓ Maximum salary\n';
        }
        if (String.isNotBlank(intent.Short_Term_Company_Size__c)) {
            message += '✓ Company size preference\n';
        }
        if (String.isNotBlank(intent.Industry_Preferences__c)) {
            message += '✓ Industry preferences\n';
        }
        
        message += '\nWould you like to update this information or continue where you left off?';
        
        List<QuickReply> replies = new List<QuickReply>();
        QuickReply yesReply = new QuickReply();
        yesReply.label = 'Update Information';
        yesReply.value = 'Update Information';
        yesReply.action = 'resume_update';
        yesReply.isPrimary = true;
        replies.add(yesReply);
        
        QuickReply noReply = new QuickReply();
        noReply.label = 'Continue Where I Left Off';
        noReply.value = 'Continue Where I Left Off';
        noReply.action = 'resume_continue';
        noReply.isPrimary = false;
        replies.add(noReply);
        
        return new ChatResponse(
            session.sessionId,
            message,
            replies,
            0,
            '0',
            true,
            'text',
            'Type your choice...'
        );
    }
    
    // Calculate next question based on filled fields
    public static Integer calculateNextQuestion(Career_Intent__c intent) {
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
        
        return 12; // All complete
    }
    
    // Get conversation history (SOQL only)
    public static List<Chat_Interaction__c> getConversationHistory(String sessionId, String contactId) {
        String query = 'SELECT Id, Name, Message_Type__c, Message_Content__c, ' +
                      'Timestamp__c, Context_Type__c, AI_Model__c, Total_Tokens__c ' +
                      'FROM Chat_Interaction__c WHERE ';
        
        if (String.isNotBlank(sessionId)) {
            query += 'Session_ID__c = :sessionId ';
        } else {
            query += 'Contact__c = :contactId ';
        }
        query += 'ORDER BY Timestamp__c ASC LIMIT 100';
        
        return Database.query(query);
    }
    
    // Get or create session - USES CLIENT SESSION ID
    private static ChatSession getOrCreateSession(String sessionId, String contactId) {
        if (String.isNotBlank(sessionId) && activeSessions.containsKey(sessionId)) {
            System.debug('♻️ Reusing existing session: ' + sessionId);
            return activeSessions.get(sessionId);
        }
        
        if (String.isNotBlank(sessionId)) {
            System.debug('🆕 Creating new session: ' + sessionId);
            ChatSession session = new ChatSession();
            session.sessionId = sessionId;
            session.contactId = contactId;
            session.createdAt = DateTime.now();
            session.lastActivity = DateTime.now();
            session.messageCount = 0;
            session.questionCount = '0';
            session.isActive = true;
            session.isResumeScenario = false;
            session.existingIntent = null;
            session.needsDataCopy = false;
            
            activeSessions.put(sessionId, session);
            return session;
        }
        
        System.debug(LoggingLevel.WARN, '⚠️ No session ID provided by client');
        ChatSession tempSession = new ChatSession();
        tempSession.sessionId = 'temp-' + String.valueOf(DateTime.now().getTime());
        tempSession.contactId = contactId;
        tempSession.createdAt = DateTime.now();
        tempSession.lastActivity = DateTime.now();
        tempSession.messageCount = 0;
        tempSession.questionCount = '0';
        tempSession.isActive = true;
        tempSession.isResumeScenario = false;
        tempSession.existingIntent = null;
        tempSession.needsDataCopy = false;
        
        return tempSession;
    }
    
    // Build chat context (SOQL only)
    private static ChatContext buildChatContext(String contactId, ChatSession session) {
        ChatContext ctx = new ChatContext();
        
        ctx.candidate = [
            SELECT Id, FirstName, LastName, Email, Title, R_ATS__Daxtra_Current_Company_Name__c,
                   R_ATS__Job_Seeking_Status__c, Profile_Completion__c, Panache_Score__c,
                   R_ATS__Desired_Salary__c, R_ATS__Availability_Date__c
            FROM Contact WHERE Id = :contactId LIMIT 1
        ];
        
        List<Career_Intent__c> intents = [
            SELECT Id, Short_Term_Goal__c, Medium_Term_Goal__c, Long_Term_Goal__c,
                   Aspirational_Goal__c, Current_State_Summary__c, Gap_Analysis__c,
                   Willing_to_Relocate__c, Short_Term_Remote__c, Min_Salary_Expactation__c,
                   Max_Salary_Expactation__c, Short_Term_Company_Size__c, Industry_Preferences__c
            FROM Career_Intent__c WHERE Contact__c = :contactId 
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        ctx.careerIntent = intents.isEmpty() ? null : intents[0];
        
        List<Career_Constraints__c> constraints = [
            SELECT Id, Preferred_Locations__c, Remote_Work_Requirement__c,
                   Min_Salary__c, Max_Salary__c, Company_Size_Preference__c,
                   Industry_Preferences__c, Culture_Preferences__c, Deal_Breakers__c
            FROM Career_Constraints__c WHERE Contact__c = :contactId LIMIT 1
        ];
        ctx.constraints = constraints.isEmpty() ? null : constraints[0];
        
        ctx.recentMessages = [
            SELECT Message_Type__c, Message_Content__c 
            FROM Chat_Interaction__c 
            WHERE Session_ID__c = :session.sessionId 
            ORDER BY Timestamp__c DESC LIMIT 10
        ];
        
        return ctx;
    }
    
    // Terminate session
    public static void endSession(String sessionId) {
        if (activeSessions.containsKey(sessionId)) {
            activeSessions.remove(sessionId);
        }
    }
    
    // Inner classes
    public class ChatSession {
        public String sessionId;
        public String contactId;
        public DateTime createdAt;
        public DateTime lastActivity;
        public Integer messageCount;
        public String questionCount;
        public Boolean isActive;
        public Boolean isResumeScenario;
        public Career_Intent__c existingIntent;
        public Boolean needsDataCopy;
        
        public ChatSession() {
            this.needsDataCopy = false;
        }
    }
    
    public class ChatContext {
        public Contact candidate;
        public Career_Intent__c careerIntent;
        public Career_Constraints__c constraints;
        public List<Chat_Interaction__c> recentMessages;
    }
    
    public class ChatResponse {
        public String sessionId;
        public String message;
        public List<QuickReply> quickReplies;
        public Integer messageCount;
        public String questionCount;
        public Long responseTime;
        public Boolean inputActive;
        public String inputType;
        public String inputPlaceholder;
        
        public ChatResponse(String sid, String msg, List<QuickReply> qr, Integer mc, String qc,
                           Boolean inputActive, String inputType, String inputPlaceholder) {
            this.sessionId = sid;
            this.message = msg;
            this.quickReplies = qr;
            this.messageCount = mc;
            this.questionCount = qc;
            this.responseTime = DateTime.now().getTime();
            this.inputActive = inputActive != null ? inputActive : true;
            this.inputType = inputType != null ? inputType : 'text';
            this.inputPlaceholder = inputPlaceholder != null ? inputPlaceholder : 'Type your message...';
        }
    }
    
    public class QuickReply {
        public String label;
        public String value;
        public String action;
        public String icon;
        public Boolean isPrimary;
        
        public QuickReply() {
            this.isPrimary = false;
        }
    }
}