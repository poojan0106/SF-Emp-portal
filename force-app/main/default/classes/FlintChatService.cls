/**
 * FlintChatService - FIXED VERSION
 * Session management + message orchestration
 */
public with sharing class FlintChatService {
    
    private static Map<String, FlintSession> activeSessions = new Map<String, FlintSession>();
    
    /**
     * Process a message and return AI response
     */
    public static FlintResponse processMessage(
        Id interactionId, String userMessage, String conversationType, String currentQuestionCount) {
        
        System.debug('═══════════════════════════════════════════════════════');
        System.debug('📥 FlintChatService.processMessage');
        System.debug('   Interaction ID: ' + interactionId);
        System.debug('   Current Question: ' + currentQuestionCount);
        System.debug('   User Message: ' + userMessage);
        System.debug('═══════════════════════════════════════════════════════');
        
        FlintSession session = getOrCreateSession(interactionId);
        
        Integer qNum = 0;
        try {
            qNum = Integer.valueOf(currentQuestionCount);
        } catch (Exception e) {
            qNum = 0;
        }
        session.questionCount = qNum;
        
        // Query interaction with ALL required fields
        List<Chat_Interaction__c> interactions = [
            SELECT Id, Account__c, Conversation_Type__c, Message_Count__c, 
                   Session_ID__c, Contact__c, Started_At__c
            FROM Chat_Interaction__c 
            WHERE Id = :interactionId
            LIMIT 1
        ];
        
        if (interactions.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'Interaction not found: ' + interactionId);
            return new FlintResponse(
                interactionId,
                'Error: Conversation not found',
                'text',
                new List<String>(),
                0,
                currentQuestionCount,
                0
            );
        }
        
        Chat_Interaction__c interaction = interactions[0];
        
        Integer nextQuestionIndex = qNum + 1;

        // Job intake questions are fixed. Do not call Claude just to ask the next scripted question.
        Long startTime = System.currentTimeMillis();
        ClaudeAPIService.ClaudeResponse aiResponse;
        if (conversationType == 'Job_Intake') {
            aiResponse = ClaudeAPIService.generateFallbackResponse(String.valueOf(nextQuestionIndex));
        } else {
            ChatContext ctx = buildChatContext(interaction.Account__c, interactionId);
            aiResponse = ClaudeAPIService.generateJobResponse(
                userMessage, ctx, conversationType, currentQuestionCount
            );
        }
        Long responseTime = System.currentTimeMillis() - startTime;
        
        // Get session data from interaction
        String sessionId = interaction.Session_ID__c;
        Id contactId = interaction.Contact__c;
        DateTime startedAt = interaction.Started_At__c;
        
        System.debug('📤 Queueing DML with session data');
        System.debug('   Session ID: ' + sessionId);
        System.debug('   Contact ID: ' + contactId);
        System.debug('   Started At: ' + startedAt);
        
        // Queue async DML with all 9 parameters
        System.enqueueJob(new FlintDMLQueueable(
            interactionId,
            userMessage,
            aiResponse.content,
            aiResponse.totalTokens,
            responseTime,
            aiResponse.extractedData,
            sessionId,
            contactId,
            startedAt
        ));
        
        session.messageCount++;
        session.lastActivity = DateTime.now();
        
        String nextQuestionCount = String.valueOf(nextQuestionIndex);
        
        System.debug('📤 Response prepared');
        System.debug('   Current: Q' + qNum);
        System.debug('   Next: Q' + nextQuestionCount);
        System.debug('═══════════════════════════════════════════════════════');
        
        return new FlintResponse(
            interactionId,
            aiResponse.content,
            detectInputType(nextQuestionIndex, aiResponse.content),
            getQuickReplies(nextQuestionIndex),
            session.messageCount,
            nextQuestionCount,
            responseTime
        );
    }
    
    /**
     * Get or create a session for this interaction
     */
    private static FlintSession getOrCreateSession(Id interactionId) {
        String key = 'flint-' + interactionId;
        
        if (activeSessions.containsKey(key)) {
            System.debug('♻️ Reusing session: ' + key);
            return activeSessions.get(key);
        }
        
        System.debug('🆕 Creating new session: ' + key);
        FlintSession session = new FlintSession();
        session.interactionId = interactionId;
        session.createdAt = DateTime.now();
        session.lastActivity = DateTime.now();
        session.messageCount = 0;
        session.questionCount = 0;
        
        activeSessions.put(key, session);
        return session;
    }
    
    /**
     * Build chat context from account and recent messages
     */
    private static ChatContext buildChatContext(Id accountId, Id interactionId) {
        ChatContext ctx = new ChatContext();
        
        // Get account details
        List<Account> accounts = [
            SELECT Id, Name, Industry, NumberOfEmployees
            FROM Account 
            WHERE Id = :accountId 
            LIMIT 1
        ];
        
        if (!accounts.isEmpty()) {
            ctx.account = accounts[0];
        } else {
            System.debug(LoggingLevel.WARN, 'Account not found: ' + accountId);
            ctx.account = null;
        }
        
        // Get recent messages - FIXED QUERY
        // Note: Assuming messages have a parent lookup field (adjust field name as needed)
        List<Chat_Interaction__c> recentMsgs = [
            SELECT Id, Message_Type__c, Message_Content__c, Timestamp__c
            FROM Chat_Interaction__c
            WHERE Chat_Interaction__c = :interactionId  // VERIFY THIS FIELD NAME IN YOUR SCHEMA
            AND Message_Type__c IN ('User', 'Assistant')
            ORDER BY Timestamp__c ASC
            LIMIT 5
        ];
        
        ctx.recentMessages = !recentMsgs.isEmpty() ? recentMsgs : new List<Chat_Interaction__c>();
        
        return ctx;
    }
    
    /**
     * Detect input type for next question
     */
    private static String detectInputType(Integer questionNum, String content) {
        return FlintJobSequence.getInputType(questionNum);
    }
    
    /**
     * Get quick reply options for next question
     */
    private static List<String> getQuickReplies(Integer questionNum) {
        return FlintJobSequence.getQuickReplies(questionNum);
    }
    
    /**
     * End a session and cleanup
     */
    public static void endSession(Id interactionId) {
        String key = 'flint-' + interactionId;
        if (activeSessions.containsKey(key)) {
            System.debug('🔚 Ending session: ' + key);
            activeSessions.remove(key);
        }
    }
    
    // ==================== INNER CLASSES ====================
    
    public class FlintSession {
        public Id interactionId;
        public Integer messageCount;
        public Integer questionCount;
        public DateTime createdAt;
        public DateTime lastActivity;
    }
    
    public class ChatContext {
        public Account account;
        public List<Chat_Interaction__c> recentMessages;
    }
    
    public class FlintResponse {
        public Id interactionId;
        public String message;
        public String inputType;
        public List<String> quickReplies;
        public Integer messageCount;
        public String questionCount;
        public Long responseTime;
        
        public FlintResponse(Id intId, String msg, String inputType, List<String> qr, 
                           Integer mc, String qc, Long rt) {
            this.interactionId = intId;
            this.message = msg;
            this.inputType = inputType;
            this.quickReplies = qr != null ? qr : new List<String>();
            this.messageCount = mc;
            this.questionCount = qc;
            this.responseTime = rt;
        }
    }
}
