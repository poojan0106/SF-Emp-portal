// ============================================================================
// FILE 3: JobListingController.cls
// @AuraEnabled controller for LWC / Experience Cloud / React frontend
// ============================================================================
public with sharing class JobListingController {

    private static Id resolveAccountId(Id accountId) {
        if (accountId != null) return accountId;
        User u = [
            SELECT ContactId, Contact.AccountId
            FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
        ];
        if (u.ContactId != null && u.Contact.AccountId != null) {
            return u.Contact.AccountId;
        }
        throw new AuraHandledException(
            'Unable to determine employer account.');
    }

    // ─── LIST VIEW ───
    @AuraEnabled(cacheable=true)
    public static JobListingDTO.JobStats getJobStats(Id accountId) {
        return JobListingService.getStats(resolveAccountId(accountId));
    }

    @AuraEnabled(cacheable=true)
    public static List<JobListingDTO.JobSummary> getJobListings(
        Id accountId, JobListingDTO.JobFilter filter
    ) {
        return JobListingService.getJobs(resolveAccountId(accountId), filter);
    }

    // ─── DETAIL VIEW ───
    @AuraEnabled(cacheable=true)
    public static JobListingDTO.JobDetail getJobDetail(Id campaignId) {
        return JobListingService.getJobDetail(campaignId);
    }

    // ─── CREATE / EDIT ───
    @AuraEnabled
    public static Id createJob(JobListingDTO.JobCreateRequest request) {
        if (request.accountId == null) {
            request.accountId = resolveAccountId(null);
        }
        return JobListingService.createJob(request);
    }

    @AuraEnabled
    public static void updateJob(
        Id campaignId, JobListingDTO.JobCreateRequest request
    ) {
        JobListingService.updateJob(campaignId, request);
    }

    // ─── STATUS ACTIONS ───
    @AuraEnabled
    public static void publishJob(Id campaignId) {
        JobListingService.publishJob(campaignId);
    }

    @AuraEnabled
    public static void holdJob(Id campaignId) {
        JobListingService.holdJob(campaignId);
    }

    @AuraEnabled
    public static void reactivateJob(Id campaignId) {
        JobListingService.reactivateJob(campaignId);
    }

    @AuraEnabled
    public static void closeJob(Id campaignId, String closeReason) {
        JobListingService.closeJob(campaignId, closeReason);
    }

    @AuraEnabled
    public static void extendDeadline(Id campaignId, Date newDeadline) {
        JobListingService.extendDeadline(campaignId, newDeadline);
    }

    @AuraEnabled
    public static Id duplicateJob(Id campaignId) {
        return JobListingService.duplicateJob(campaignId);
    }

    // ─── PIPELINE MANAGEMENT ───
    @AuraEnabled
    public static void updateCandidateStatus(
        Id memberId, String newStatus, String notes
    ) {
        JobListingService.updateCandidateStatus(memberId, newStatus, notes);
    }

    @AuraEnabled
    public static void bulkUpdateCandidateStatus(
        List<Id> memberIds, String newStatus
    ) {
        JobListingService.bulkUpdateCandidateStatus(memberIds, newStatus);
    }

    @AuraEnabled
    public static Id addCandidateToJob(
        Id campaignId, Id contactId, String initialStatus
    ) {
        return JobListingService.addCandidateToJob(
            campaignId, contactId, initialStatus);
    }

    @AuraEnabled
    public static Id addFromTalentPool(Id jobCampaignId, Id poolMemberId) {
        return JobListingService.addFromTalentPool(
            jobCampaignId, poolMemberId);
    }

    // ─── BULK ACTIONS ───
    @AuraEnabled
    public static void bulkCloseJobs(List<Id> ids, String reason) {
        JobListingService.bulkCloseJobs(ids, reason);
    }

    @AuraEnabled
    public static void bulkArchiveJobs(List<Id> ids) {
        JobListingService.bulkArchiveJobs(ids);
    }

    // ─── UTILITIES ───
    @AuraEnabled(cacheable=true)
    public static List<String> getAvailableStatuses(String recordTypeName) {
        List<String> statuses = new List<String>();
        for (Campaign_Member_Status__mdt cms :
             Campaign_Member_Status__mdt.getAll().values()) {
            statuses.add(cms.Status_Name__c);
        }
        statuses.sort();
        return statuses;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> searchSkills(String searchTerm) {
        String term = '%' + String.escapeSingleQuotes(searchTerm) + '%';
        List<Map<String, String>> results = new List<Map<String, String>>();
        for (R_ATS__Topic_Library__c sl : [
            SELECT Id, Name, R_ATS__Category_Level_1__c
            FROM R_ATS__Topic_Library__c WHERE Name LIKE :term
            ORDER BY Name LIMIT 20
        ]) {
            results.add(new Map<String, String>{
                'id' => sl.Id, 'name' => sl.Name,
                'category' => sl.R_ATS__Category_Level_1__c
            });
        }
        return results;
    }
}