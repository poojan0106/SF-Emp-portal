public with sharing class AIRetryService implements Schedulable {
    private static final Integer MAX_ATTEMPTS = 3;
    private static final Integer RETRY_DELAY_MINUTES = 30;

    public static void enqueue(Id contactId, Id campaignMemberId, String operation, String payload, String errorMessage) {
        if (!Schema.getGlobalDescribe().containsKey('AI_Retry__c')) return;

        try {
            List<AI_Retry__c> existing = [
                SELECT Id
                FROM AI_Retry__c
                WHERE Status__c IN ('Pending', 'Processing')
                AND Operation__c = :operation
                AND Contact__c = :contactId
                LIMIT 1
            ];
            if (!existing.isEmpty()) return;

            insert new AI_Retry__c(
                Contact__c = contactId,
                Campaign_Member__c = campaignMemberId,
                Operation__c = operation,
                Payload__c = safe(payload),
                Status__c = 'Pending',
                Attempts__c = 0,
                Last_Error__c = safe(errorMessage),
                Next_Run_At__c = System.now().addMinutes(RETRY_DELAY_MINUTES)
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'AI retry enqueue skipped: ' + e.getMessage());
        }
    }

    public void execute(SchedulableContext context) {
        runDueRetries(25);
    }

    public static void runDueRetries(Integer limitSize) {
        if (!Schema.getGlobalDescribe().containsKey('AI_Retry__c')) return;
        Integer rowLimit = limitSize == null || limitSize <= 0 ? 25 : limitSize;
        Datetime nowValue = System.now();

        List<AI_Retry__c> rows = [
            SELECT Id, Contact__c, Campaign_Member__c, Operation__c, Payload__c, Attempts__c, Status__c
            FROM AI_Retry__c
            WHERE Status__c IN ('Pending', 'Failed')
            AND (Next_Run_At__c = null OR Next_Run_At__c <= :nowValue)
            ORDER BY CreatedDate ASC
            LIMIT :rowLimit
        ];

        for (AI_Retry__c row : rows) {
            process(row);
        }
    }

    private static void process(AI_Retry__c row) {
        if (row == null) return;
        Decimal attempts = row.Attempts__c == null ? 0 : row.Attempts__c;
        update new AI_Retry__c(Id = row.Id, Status__c = 'Processing', Attempts__c = attempts + 1);

        try {
            Boolean success = false;
            if (row.Operation__c == 'CV Enhancement' && row.Contact__c != null) {
                success = AICVEnhancementService.enhanceContactFromRetry(row.Contact__c);
            } else if (row.Operation__c == 'CV Scoring' && String.isNotBlank(row.Campaign_Member__c)) {
                CandidateCVScoringService.scoreCampaignMember((Id) row.Campaign_Member__c);
                success = true;
            }

            update new AI_Retry__c(
                Id = row.Id,
                Status__c = success ? 'Complete' : retryStatus(attempts + 1),
                Next_Run_At__c = success ? null : System.now().addMinutes(RETRY_DELAY_MINUTES),
                Last_Error__c = success ? null : 'AI operation still failed or returned fallback.'
            );
        } catch (Exception e) {
            update new AI_Retry__c(
                Id = row.Id,
                Status__c = retryStatus(attempts + 1),
                Next_Run_At__c = attempts + 1 >= MAX_ATTEMPTS ? null : System.now().addMinutes(RETRY_DELAY_MINUTES),
                Last_Error__c = safe(e.getMessage())
            );
        }
    }

    private static String retryStatus(Decimal attempts) {
        return attempts >= MAX_ATTEMPTS ? 'Failed' : 'Pending';
    }

    private static String safe(String value) {
        if (String.isBlank(value)) return value;
        return value.length() > 32768 ? value.substring(0, 32768) : value;
    }
}
