public with sharing class AIRetryAdminController {
    public class RetryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String operation;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal attempts;
        @AuraEnabled public String lastError;
        @AuraEnabled public Datetime nextRunAt;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String contactUrl;
        @AuraEnabled public Id campaignMemberId;
        @AuraEnabled public String campaignMemberUrl;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<RetryRow> listRetries() {
        List<RetryRow> result = new List<RetryRow>();
        if (!Schema.getGlobalDescribe().containsKey('AI_Retry__c')) return result;

        for (AI_Retry__c row : [
            SELECT Id, Operation__c, Status__c, Attempts__c, Last_Error__c, Next_Run_At__c,
                   Contact__c, Campaign_Member__c, CreatedDate
            FROM AI_Retry__c
            WHERE Status__c IN ('Pending', 'Failed', 'Processing', 'Complete')
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            RetryRow item = new RetryRow();
            item.id = row.Id;
            item.operation = row.Operation__c;
            item.status = row.Status__c;
            item.attempts = row.Attempts__c;
            item.lastError = row.Last_Error__c;
            item.nextRunAt = row.Next_Run_At__c;
            item.contactId = row.Contact__c;
            item.contactUrl = row.Contact__c == null ? null : '/' + row.Contact__c;
            item.campaignMemberId = row.Campaign_Member__c;
            item.campaignMemberUrl = row.Campaign_Member__c == null ? null : '/' + row.Campaign_Member__c;
            item.createdDate = row.CreatedDate;
            result.add(item);
        }
        return result;
    }

    @AuraEnabled
    public static void retryNow(List<Id> retryIds) {
        if (!Schema.getGlobalDescribe().containsKey('AI_Retry__c')) return;

        if (retryIds != null && !retryIds.isEmpty()) {
            List<AI_Retry__c> updates = new List<AI_Retry__c>();
            for (AI_Retry__c row : [
                SELECT Id
                FROM AI_Retry__c
                WHERE Id IN :retryIds
            ]) {
                updates.add(new AI_Retry__c(Id = row.Id, Status__c = 'Pending', Next_Run_At__c = System.now()));
            }
            if (!updates.isEmpty()) update updates;
        }
        AIRetryService.runDueRetries(50);
    }
}