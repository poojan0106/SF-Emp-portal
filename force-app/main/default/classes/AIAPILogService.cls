public with sharing class AIAPILogService {
    private static final Integer LONG_TEXT_LIMIT = 32768;

    public class LogEntry {
        public Id contactId;
        public Id campaignMemberId;
        public String operation;
        public String requestType;
        public String requestPayload;
        public String responsePayload;
        public String status;
        public String errorMessage;
        public String model;
        public Integer inputTokens;
        public Integer outputTokens;
        public Integer totalTokens;
        public Decimal cost;
        public Integer durationMs;
        public Integer httpStatusCode;
    }

    public static void logClaudeCall(LogEntry entry) {
        if (entry == null || !Schema.getGlobalDescribe().containsKey('AI_API_Log__c')) return;

        try {
            SObject logRow = Schema.getGlobalDescribe().get('AI_API_Log__c').newSObject();
            put(logRow, 'AI_Provider__c', 'Anthropic_Claude');
            put(logRow, 'Request_Type__c', normalizeRequestType(entry.requestType, entry.operation));
            put(logRow, 'Operation__c', safe(entry.operation, 255));
            put(logRow, 'Status__c', String.isBlank(entry.status) ? 'Success' : entry.status);
            put(logRow, 'Related_Contact__c', entry.contactId);
            put(logRow, 'Campaign_Member__c', entry.campaignMemberId);
            put(logRow, 'Request_Payload__c', safe(entry.requestPayload, LONG_TEXT_LIMIT));
            put(logRow, 'Response_Payload__c', safe(entry.responsePayload, LONG_TEXT_LIMIT));
            put(logRow, 'Error_Message__c', safe(entry.errorMessage, 255));
            put(logRow, 'Model__c', safe(entry.model, 100));
            put(logRow, 'Token_Count_Input__c', entry.inputTokens);
            put(logRow, 'Token_Count_Output__c', entry.outputTokens);
            put(logRow, 'Token_Count__c', entry.totalTokens);
            put(logRow, 'Estimated_Cost__c', entry.cost);
            put(logRow, 'Processing_Time_ms__c', entry.durationMs);
            put(logRow, 'HTTP_Status_Code__c', entry.httpStatusCode);
            insert logRow;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AI API log skipped: ' + e.getMessage());
        }
    }

    public static void logSuccess(String operation, Id contactId, Id campaignMemberId, String requestPayload, String responsePayload, Integer durationMs) {
        LogEntry entry = new LogEntry();
        entry.operation = operation;
        entry.requestType = requestTypeForOperation(operation);
        entry.contactId = contactId;
        entry.campaignMemberId = campaignMemberId;
        entry.requestPayload = requestPayload;
        entry.responsePayload = responsePayload;
        entry.status = 'Success';
        entry.durationMs = durationMs;
        logClaudeCall(entry);
    }

    public static void logFailure(String operation, Id contactId, Id campaignMemberId, String requestPayload, String errorMessage, Integer durationMs) {
        LogEntry entry = new LogEntry();
        entry.operation = operation;
        entry.requestType = requestTypeForOperation(operation);
        entry.contactId = contactId;
        entry.campaignMemberId = campaignMemberId;
        entry.requestPayload = requestPayload;
        entry.errorMessage = errorMessage;
        entry.status = 'Failed';
        entry.durationMs = durationMs;
        logClaudeCall(entry);
    }

    public static String requestTypeForOperation(String operation) {
        String op = String.isBlank(operation) ? '' : operation.toLowerCase();
        if (op.contains('skill')) return 'Skill_Extract';
        if (op.contains('summary')) return 'Summary_Generate';
        if (op.contains('scor')) return 'CV_Match';
        if (op.contains('match')) return 'Job_Match';
        if (op.contains('parse')) return 'CV_Parse';
        if (op.contains('chat')) return 'Chat_Completion';
        return 'Other';
    }

    private static String normalizeRequestType(String requestType, String operation) {
        String value = String.isBlank(requestType) ? requestTypeForOperation(operation) : requestType;
        Set<String> allowed = new Set<String>{
            'CV_Parse', 'CV_Match', 'Job_Match', 'Skill_Extract', 'Summary_Generate', 'Chat_Completion', 'Other'
        };
        return allowed.contains(value) ? value : 'Other';
    }

    private static void put(SObject row, String fieldName, Object value) {
        if (value == null) return;
        if (row.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) row.put(fieldName, value);
    }

    private static String safe(String value, Integer maxLength) {
        if (String.isBlank(value)) return value;
        return value.length() > maxLength ? value.substring(0, maxLength) : value;
    }
}
