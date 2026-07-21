/**
 * LeagueMembershipService
 * Source of truth for swipe-created League/Talent Pool records.
 *
 * User-story object model:
 * - Talent_League__c = employer Talent Pool / League
 * - League_Membership__c = candidate pool member / League entry
 *
 * One right swipe creates/updates:
 * - CampaignMember under each active Campaign for employer
 * - one optional Talent_League__c per employer
 * - one optional League_Membership__c per employer + candidate
 */
public with sharing class LeagueMembershipService {
    public static final String LEAGUE_STATUS_ACTIVE = 'Active';
    public static final String MEMBERSHIP_STATUS_IN_LEAGUE = 'In League';

    public static void addRightSwipesToLeague(List<Swipe_Event__c> swipes) {
        if (swipes == null || swipes.isEmpty()) return;

        List<Swipe_Event__c> rightSwipes = new List<Swipe_Event__c>();
        Set<Id> employerIds = new Set<Id>();
        Set<Id> candidateIds = new Set<Id>();

        for (Swipe_Event__c swipe : swipes) {
            if (swipe.Direction__c == 'Right' && swipe.Candidate__c != null && swipe.Employers__c != null) {
                rightSwipes.add(swipe);
                employerIds.add(swipe.Employers__c);
                candidateIds.add(swipe.Candidate__c);
            }
        }

        if (rightSwipes.isEmpty()) return;

        addSwipesToActiveCampaigns(rightSwipes, employerIds, candidateIds);

        Map<Id, Talent_League__c> leaguesByEmployer = getOrCreateLeagues(employerIds);
        Map<String, League_Membership__c> existingByKey = getExistingMemberships(employerIds, candidateIds);

        List<League_Membership__c> toInsert = new List<League_Membership__c>();
        List<League_Membership__c> toUpdate = new List<League_Membership__c>();
        Map<Id, League_Membership__c> membershipBySwipe = new Map<Id, League_Membership__c>();

        for (Swipe_Event__c swipe : rightSwipes) {
            Talent_League__c league = leaguesByEmployer.get(swipe.Employers__c);
            if (league == null) continue;

            String key = buildKey(swipe.Employers__c, swipe.Candidate__c);
            League_Membership__c existing = existingByKey.get(key);

            if (existing == null) {
                League_Membership__c membership = new League_Membership__c(
                    Talent_League__c = league.Id,
                    Employer__c = swipe.Employers__c,
                    Candidate__c = swipe.Candidate__c,
                    Status__c = MEMBERSHIP_STATUS_IN_LEAGUE,
                    Joined_Date__c = System.now(),
                    Swipe_Event__c = swipe.Id,
                    Identity_Reveal_Status__c = 'Not Requested',
                    Full_Profile_Unlocked__c = false,
                    Anonymized_Candidate_Key__c = buildAnonymizedKey(swipe.Id)
                );
                toInsert.add(membership);
                existingByKey.put(key, membership);
                membershipBySwipe.put(swipe.Id, membership);
            } else {
                existing.Status__c = MEMBERSHIP_STATUS_IN_LEAGUE;
                existing.Swipe_Event__c = swipe.Id;
                if (existing.Joined_Date__c == null) {
                    existing.Joined_Date__c = System.now();
                }
                if (String.isBlank(existing.Anonymized_Candidate_Key__c)) {
                    existing.Anonymized_Candidate_Key__c = buildAnonymizedKey(swipe.Id);
                }
                toUpdate.add(existing);
                membershipBySwipe.put(swipe.Id, existing);
            }
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(toInsert, false);
            for (Integer i = 0; i < insertResults.size(); i++) {
                if (!insertResults[i].isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'League membership insert failed: ' + insertResults[i].getErrors()[0].getMessage());
                }
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] updateResults = Database.update(toUpdate, false);
            for (Integer i = 0; i < updateResults.size(); i++) {
                if (!updateResults[i].isSuccess()) {
                    System.debug(LoggingLevel.ERROR, 'League membership update failed: ' + updateResults[i].getErrors()[0].getMessage());
                }
            }
        }

        linkSwipes(rightSwipes, membershipBySwipe);
    }

    private static void addSwipesToActiveCampaigns(List<Swipe_Event__c> rightSwipes, Set<Id> employerIds, Set<Id> candidateIds) {
        if (rightSwipes.isEmpty() || employerIds.isEmpty() || candidateIds.isEmpty()) return;

        List<Campaign> campaigns = [
            SELECT Id, Employer__c
            FROM Campaign
            WHERE Employer__c IN :employerIds
            AND IsActive = true
            AND Status = 'Active'
        ];
        if (campaigns.isEmpty()) return;

        Set<Id> campaignIds = new Set<Id>();
        Map<Id, List<Campaign>> campaignsByEmployer = new Map<Id, List<Campaign>>();
        for (Campaign campaign : campaigns) {
            campaignIds.add(campaign.Id);
            if (!campaignsByEmployer.containsKey(campaign.Employer__c)) {
                campaignsByEmployer.put(campaign.Employer__c, new List<Campaign>());
            }
            campaignsByEmployer.get(campaign.Employer__c).add(campaign);
        }

        ensureCampaignMemberStatuses(campaignIds);

        Map<String, CampaignMember> existingByKey = new Map<String, CampaignMember>();
        for (CampaignMember member : [
            SELECT Id, CampaignId, ContactId, Status, Swipe_Event__c
            FROM CampaignMember
            WHERE CampaignId IN :campaignIds
            AND ContactId IN :candidateIds
        ]) {
            existingByKey.put(buildKey(member.CampaignId, member.ContactId), member);
        }

        List<CampaignMember> toInsert = new List<CampaignMember>();
        List<CampaignMember> toUpdate = new List<CampaignMember>();

        for (Swipe_Event__c swipe : rightSwipes) {
            List<Campaign> employerCampaigns = campaignsByEmployer.get(swipe.Employers__c);
            if (employerCampaigns == null) continue;

            for (Campaign campaign : employerCampaigns) {
                String key = buildKey(campaign.Id, swipe.Candidate__c);
                CampaignMember existing = existingByKey.get(key);
                if (existing == null) {
                    CampaignMember member = new CampaignMember(
                        CampaignId = campaign.Id,
                        ContactId = swipe.Candidate__c,
                        Status = MEMBERSHIP_STATUS_IN_LEAGUE,
                        Interest_Date__c = System.now(),
                        Swipe_Event__c = swipe.Id,
                        Sentiment_Tags__c = swipe.Sentiment_Tags__c,
                        Identity_Reveal_Status__c = 'Not Requested',
                        Full_Profile_Unlocked__c = false
                    );
                    toInsert.add(member);
                    existingByKey.put(key, member);
                } else {
                    existing.Status = MEMBERSHIP_STATUS_IN_LEAGUE;
                    existing.Swipe_Event__c = swipe.Id;
                    existing.Sentiment_Tags__c = swipe.Sentiment_Tags__c;
                    toUpdate.add(existing);
                }
            }
        }

        if (!toInsert.isEmpty()) Database.insert(toInsert, false);
        if (!toUpdate.isEmpty()) Database.update(toUpdate, false);
    }

    private static void ensureCampaignMemberStatuses(Set<Id> campaignIds) {
        Set<String> neededStatuses = new Set<String>{
            MEMBERSHIP_STATUS_IN_LEAGUE,
            'Interview Requested',
            'Interview Confirmed',
            'Interview Rejected',
            'Reschedule Requested'
        };
        Set<String> existingKeys = new Set<String>();
        for (CampaignMemberStatus statusRecord : [
            SELECT CampaignId, Label
            FROM CampaignMemberStatus
            WHERE CampaignId IN :campaignIds
            AND Label IN :neededStatuses
        ]) {
            existingKeys.add(String.valueOf(statusRecord.CampaignId) + '|' + statusRecord.Label);
        }

        List<CampaignMemberStatus> toInsert = new List<CampaignMemberStatus>();
        Map<String, Integer> sortOrderByStatus = new Map<String, Integer>{
            MEMBERSHIP_STATUS_IN_LEAGUE => 20,
            'Interview Requested' => 50,
            'Interview Confirmed' => 60,
            'Interview Rejected' => 65,
            'Reschedule Requested' => 70
        };
        for (Id campaignId : campaignIds) {
            for (String statusLabel : neededStatuses) {
                if (existingKeys.contains(String.valueOf(campaignId) + '|' + statusLabel)) continue;
                toInsert.add(new CampaignMemberStatus(
                    CampaignId = campaignId,
                    Label = statusLabel,
                    HasResponded = true,
                    IsDefault = false,
                    SortOrder = sortOrderByStatus.get(statusLabel)
                ));
            }
        }
        if (!toInsert.isEmpty()) Database.insert(toInsert, false);
    }

    private static Map<Id, Talent_League__c> getOrCreateLeagues(Set<Id> employerIds) {
        Map<Id, Talent_League__c> leaguesByEmployer = new Map<Id, Talent_League__c>();

        for (Talent_League__c league : [
            SELECT Id, Employer__c, Status__c
            FROM Talent_League__c
            WHERE Employer__c IN :employerIds
        ]) {
            if (!leaguesByEmployer.containsKey(league.Employer__c)) {
                leaguesByEmployer.put(league.Employer__c, league);
            }
        }

        List<Talent_League__c> toInsert = new List<Talent_League__c>();
        for (Id employerId : employerIds) {
            if (!leaguesByEmployer.containsKey(employerId)) {
                toInsert.add(new Talent_League__c(
                    Employer__c = employerId,
                    Status__c = LEAGUE_STATUS_ACTIVE,
                    Source__c = 'Swipe',
                    Opened_Date__c = System.now(),
                    Active_Job_Count__c = 1
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
            for (Talent_League__c league : toInsert) {
                leaguesByEmployer.put(league.Employer__c, league);
            }
        }

        return leaguesByEmployer;
    }

    private static Map<String, League_Membership__c> getExistingMemberships(Set<Id> employerIds, Set<Id> candidateIds) {
        Map<String, League_Membership__c> existingByKey = new Map<String, League_Membership__c>();

        for (League_Membership__c membership : [
            SELECT Id, Employer__c, Candidate__c, Status__c, Joined_Date__c, Swipe_Event__c, Anonymized_Candidate_Key__c
            FROM League_Membership__c
            WHERE Employer__c IN :employerIds
            AND Candidate__c IN :candidateIds
        ]) {
            existingByKey.put(buildKey(membership.Employer__c, membership.Candidate__c), membership);
        }

        return existingByKey;
    }

    private static void linkSwipes(List<Swipe_Event__c> swipes, Map<Id, League_Membership__c> membershipBySwipe) {
        List<Swipe_Event__c> toUpdate = new List<Swipe_Event__c>();

        for (Swipe_Event__c swipe : swipes) {
            League_Membership__c membership = membershipBySwipe.get(swipe.Id);
            if (membership != null && membership.Id != null) {
                toUpdate.add(new Swipe_Event__c(
                    Id = swipe.Id,
                    League_Membership__c = membership.Id,
                    Added_To_Pool__c = true
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    private static String buildKey(Id employerId, Id candidateId) {
        return String.valueOf(employerId) + '-' + String.valueOf(candidateId);
    }

    private static String buildAnonymizedKey(Id sourceId) {
        String raw = String.valueOf(sourceId);
        Integer start = Math.max(0, raw.length() - 8);
        return 'Candidate - ' + raw.substring(start);
    }
}
