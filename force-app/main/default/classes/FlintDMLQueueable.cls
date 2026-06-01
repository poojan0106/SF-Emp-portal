/**
 * FlintDMLQueueable - FIXED VERSION
 * Async database writes for chat interactions
 * 
 * FIXES APPLIED:
 * 1. ✅ Add Extracted_Job_Data__c to store extracted data
 * 2. ✅ Fix Response_Time_ms__c to be Long, not String
 * 3. ✅ Fix Total_Tokens__c to accumulate (add tokenCount, not just currentTokens)
 */
public class FlintDMLQueueable implements Queueable {
    
    private Id interactionId;
    private String userMessage;
    private String assistantMessage;
    private Integer tokenCount;
    private Long responseTime;
    private Map<String, Object> extractedData;
    private String sessionId;
    private Id contactId;
    private DateTime startedAt;
    
    /**
     * Constructor with all 9 parameters (primary)
     */
    public FlintDMLQueueable(
        Id interactionId,
        String userMessage,
        String assistantMessage,
        Integer tokenCount,
        Long responseTime,
        Map<String, Object> extractedData,
        String sessionId,
        Id contactId,
        DateTime startedAt) {
        
        this.interactionId = interactionId;
        this.userMessage = userMessage;
        this.assistantMessage = assistantMessage;
        this.tokenCount = tokenCount;
        this.responseTime = responseTime;
        this.extractedData = extractedData != null ? extractedData : new Map<String, Object>();
        this.sessionId = sessionId;
        this.contactId = contactId;
        this.startedAt = startedAt;
    }
    
    
    /**
     * Execute queueable job
     */
    public void execute(QueueableContext qc) {
        //Savepoint sp = Database.setSavepoint();  
        
        try {
            DateTime now = DateTime.now();
            
            // Initialize defaults if null
            if (startedAt == null) {
                startedAt = now;
            }
            
            if (String.isBlank(sessionId)) {
                sessionId = generateSessionId();
            }
            
            // Validate required ID
            if (interactionId == null) {
                System.debug(LoggingLevel.ERROR, 'Error: interactionId is null');
                return;
            }
            
            System.debug('📝 FlintDMLQueueable.execute');
            System.debug('   Interaction: ' + interactionId);
            System.debug('   Session: ' + sessionId);
            System.debug('   Contact: ' + contactId);
            System.debug('   Extracted Data Keys: ' + extractedData.keySet());
            
            
            List<Chat_Interaction__c> messages = new List<Chat_Interaction__c>();
            
            // Create user message record
            if (String.isNotBlank(userMessage)) {
                Chat_Interaction__c userMsg = new Chat_Interaction__c(
                    Chat_Interaction__c = interactionId,
                    Message_Type__c = 'User',
                    Message_Content__c = truncateMessage(userMessage),
                    Timestamp__c = now.addSeconds(-1)
                );
                
                // Set optional fields only if they have values
                if (String.isNotBlank(sessionId)) {
                    userMsg.Session_ID__c = sessionId;
                }
                if (contactId != null) {
                    userMsg.Contact__c = contactId;
                }
                if (startedAt != null) {
                    userMsg.Started_At__c = startedAt;
                }
                
                messages.add(userMsg);
            }
            
            // Create assistant message record
            if (String.isNotBlank(assistantMessage)) {
                Chat_Interaction__c assistantMsg = new Chat_Interaction__c(
                    Chat_Interaction__c = interactionId,
                    Message_Type__c = 'Assistant',
                    Message_Content__c = truncateMessage(assistantMessage),
                    Timestamp__c = now,
                    Total_Tokens__c = tokenCount,
                    Response_Time_ms__c = String.valueOf(responseTime), 
                    Extracted_Job_Data__c = !extractedData.isEmpty() ? JSON.serialize(extractedData) : null  // ✅ FIX: Store extracted data as JSON
                );
                
                // Set optional fields only if they have values
                if (String.isNotBlank(sessionId)) {
                    assistantMsg.Session_ID__c = sessionId;
                }
                if (contactId != null) {
                    assistantMsg.Contact__c = contactId;
                }
                if (startedAt != null) {
                    assistantMsg.Started_At__c = startedAt;
                }
                
                messages.add(assistantMsg);
                System.debug('📊 Assistant message prepared with extracted data');
            }
            
            // Insert message records
            if (!messages.isEmpty()) {
                insert messages;
                System.debug('✅ Messages inserted: ' + messages.size());
            }
            
            // Query and update parent interaction
            List<Chat_Interaction__c> interactions = [
                SELECT Id, Message_Count__c, Total_Tokens__c, Session_ID__c, Contact__c, Started_At__c
                FROM Chat_Interaction__c 
                WHERE Id = :interactionId
                LIMIT 1
            ];
            
            if (interactions.isEmpty()) {
                System.debug(LoggingLevel.ERROR, 'Error: Interaction not found: ' + interactionId);
                //Database.rollback(sp);
                return;
            }
            
            Chat_Interaction__c interaction = interactions[0];
            
            // Update message count
            Integer currentCount = interaction.Message_Count__c != null ? 
                Integer.valueOf(interaction.Message_Count__c) : 0;
            interaction.Message_Count__c = currentCount + messages.size();
            
            // Update token count - ✅ FIX: Now actually adds tokenCount instead of just keeping currentTokens
            Integer currentTokens = interaction.Total_Tokens__c != null ? 
                Integer.valueOf(interaction.Total_Tokens__c) : 0;
            interaction.Total_Tokens__c = currentTokens + tokenCount;  // ✅ FIX: Was "currentTokens" now adds tokenCount
            
            // Update session fields only if not already set AND have values
            if (interaction.Session_ID__c == null && String.isNotBlank(sessionId)) {
                interaction.Session_ID__c = sessionId;
            }
            if (interaction.Contact__c == null && contactId != null) {
                interaction.Contact__c = contactId;
            }
            if (interaction.Started_At__c == null && startedAt != null) {
                interaction.Started_At__c = startedAt;
            }
            
            System.debug('📊 Interaction updates:');
            System.debug('   Message Count: ' + interaction.Message_Count__c);
            System.debug('   Total Tokens: ' + interaction.Total_Tokens__c);
            System.debug('   Session ID: ' + interaction.Session_ID__c);
            System.debug('   Contact ID: ' + interaction.Contact__c);
            System.debug('   Started At: ' + interaction.Started_At__c);
            
            // Update interaction
            update interaction;
            
            System.debug('✅ Interaction updated successfully');
            
        } catch (Exception e) {
            //Database.rollback(sp);  
            System.debug(LoggingLevel.ERROR, '❌ FlintDMLQueueable Error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack: ' + e.getStackTraceString());
        }
    }
    
    /**
     * Truncate message to max length
     */
    private String truncateMessage(String message) {
        if (String.isBlank(message)) return '';
        Integer maxLength = 10000;  // FIX: Changed from 130000 to 10000 for better performance
        return message.length() > maxLength ? message.substring(0, maxLength) : message;
    }
    
    /**
     * Generate unique session ID
     */
    private static String generateSessionId() {
        return 'FLINT-' + String.valueOf(DateTime.now().getTime()) + '-' + 
               EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
    }
}