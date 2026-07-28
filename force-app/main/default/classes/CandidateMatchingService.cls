/**
 * CandidateMatchingService
 * Backward-compatible entry points for candidate/job scoring.
 * Legacy match formula removed; scoring now uses AI_CV_Score__c.
 */
public class CandidateMatchingService {

    public static void matchCandidatesToJob(Id jobId, Id accountId) {
        if (jobId == null) return;

        List<CampaignMember> members = [
            SELECT Id, ContactId
            FROM CampaignMember
            WHERE CampaignId = :jobId
        ];
        if (members.isEmpty()) return;

        Set<Id> contactIds = new Set<Id>();
        for (CampaignMember member : members) {
            if (member.ContactId != null) contactIds.add(member.ContactId);
        }

        for (Id contactId : contactIds) {
            CandidateCVScoringService.scoreCampaignMembersForContact(contactId);
        }

        List<CampaignMember> scoredMembers = [
            SELECT Id, ContactId, AI_CV_Score__c, Campaign.Name, Campaign.Employer__r.Name
            FROM CampaignMember
            WHERE CampaignId = :jobId
        ];

        Integer matchingCount = 0;
        Set<Id> notifiedContactIds = new Set<Id>();
        List<NotificationService.NotificationRequest> notificationRequests = new List<NotificationService.NotificationRequest>();

        for (CampaignMember member : scoredMembers) {
            Decimal score = member.AI_CV_Score__c == null ? 0 : member.AI_CV_Score__c;
            if (score >= 70 && member.ContactId != null && !notifiedContactIds.contains(member.ContactId)) {
                matchingCount++;
                notifiedContactIds.add(member.ContactId);

                NotificationService.NotificationRequest request = new NotificationService.NotificationRequest();
                request.recipientId = member.ContactId;
                request.notificationType = 'Job_Match';
                request.title = 'New job match: ' + member.Campaign.Name;
                request.description = member.Campaign.Name + ' Position at ' + member.Campaign.Employer__r.Name +
                    ' matches your career profile.';
                request.linkTo = '/discover-employers';
                request.priority = 'Normal';
                notificationRequests.add(request);
            }
        }

        if (!notificationRequests.isEmpty()) {
            NotificationService.notifyMany(notificationRequests);
        }

        Campaign job = new Campaign(Id = jobId);
        job.Matching_Candidate_Count__c = matchingCount;
        update job;
    }

    public static void calculateMatchScore(Id campaignMemberId) {
        CandidateCVScoringService.scoreCampaignMember(campaignMemberId);
    }
}
