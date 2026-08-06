public with sharing class AICVScoringBatch implements Database.Batchable<SObject>, Schedulable {
    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, ContactId
            FROM CampaignMember
            WHERE ContactId != null
            AND CampaignId != null
            AND (AI_CV_Score__c = null OR LastModifiedDate = LAST_N_DAYS:30)
        ]);
    }

    public void execute(Database.BatchableContext context, List<CampaignMember> scope) {
        Set<Id> contactIds = new Set<Id>();
        for (CampaignMember member : scope) {
            if (member.ContactId != null) contactIds.add(member.ContactId);
        }
        for (Id contactId : contactIds) {
            try {
                CandidateCVScoringService.scoreCampaignMembersForContact(contactId);
            } catch (Exception e) {
                // Retry disabled per current requirement. Re-enable to queue failed scoring batch rows.
                // AIRetryService.enqueue(contactId, null, 'CV Scoring', 'Batch scoring for contact', e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext context) {}

    public void execute(SchedulableContext context) {
        Database.executeBatch(new AICVScoringBatch(), 100);
    }
}