/**
 * SwipeEventHandler
 * Processes swipe events and updates talent pools
 */
public class SwipeEventHandlers {
    
    public static void processRightSwipes(List<Swipe_Event__c> swipes) {
        List<Id> swipeIds = new List<Id>();
        for (Swipe_Event__c swipe : swipes) {
            swipeIds.add(swipe.Id);
        }
        processRightSwipesAsync(swipeIds);
    }
    
    @Future
    public static void processRightSwipesAsync(List<Id> swipeIds) {
        List<Swipe_Event__c> swipes = [
            SELECT Id, Candidate__c, Employers__c, Sentiment_Tags__c
            FROM Swipe_Event__c
            WHERE Id IN :swipeIds
        ];
        
        Set<Id> employerIds = new Set<Id>();
        for (Swipe_Event__c swipe : swipes) {
            employerIds.add(swipe.Employers__c);
        }
        
        Map<Id, Campaign> employerPools = getOrCreateTalentPools(employerIds);
        
        List<CampaignMember> newMembers = new List<CampaignMember>();
        List<Swipe_Event__c> swipesToUpdate = new List<Swipe_Event__c>();
        
        for (Swipe_Event__c swipe : swipes) {
            Campaign pool = employerPools.get(swipe.Employers__c);
            
            CampaignMember member = new CampaignMember(
                CampaignId = pool.Id,
                ContactId = swipe.Candidate__c,
                Status = 'Interested',
                Interest_Source__c = 'Swipe',
                Interest_Date__c = DateTime.now(),
                Sentiment_Tags__c = swipe.Sentiment_Tags__c,
                Swipe_Event__c = swipe.Id
            );
            newMembers.add(member);
            
            swipe.Added_To_Pool__c = true;
            swipesToUpdate.add(swipe);
        }
        
        Database.SaveResult[] results = Database.insert(newMembers, false);

        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                swipesToUpdate[i].Campaign_Member__c = results[i].getId();
                System.debug('[CampaignMember INSERT SUCCESS] ID: ' + results[i].getId() + ', Swipe_Event__c should be set');
                CandidateMatchingService.calculateMatchScore(results[i].getId());
            } else {
                System.debug('[CampaignMember INSERT ERROR] Error Details:');
                for (Database.Error err : results[i].getErrors()) {
                    System.debug('  - Status Code: ' + err.getStatusCode());
                    System.debug('  - Message: ' + err.getMessage());
                    System.debug('  - Fields: ' + err.getFields());
                }
            }
        }
        
        update swipesToUpdate;
    }
    
    private static Map<Id, Campaign> getOrCreateTalentPools(Set<Id> employerIds) {
        Map<Id, Campaign> existingPools = new Map<Id, Campaign>();
        
        for (Campaign pool : [
            SELECT Id, Employer__c
            FROM Campaign
            WHERE RecordType.DeveloperName = 'Talent_Pool'
            AND Employer__c IN :employerIds
            AND Pool_Type__c = 'Employer_Interest'
        ]) {
            existingPools.put(pool.Employer__c, pool);
        }
        
        List<Campaign> newPools = new List<Campaign>();
        Map<Id, Account> employers = new Map<Id, Account>([
            SELECT Id, Name FROM Account WHERE Id IN :employerIds
        ]);
        
        Id talentPoolRT = Schema.SObjectType.Campaign.getRecordTypeInfosByDeveloperName()
            .get('Talent_Pool').getRecordTypeId();
        
        for (Id employerId : employerIds) {
            if (!existingPools.containsKey(employerId)) {
                Campaign pool = new Campaign(
                    Name = employers.get(employerId).Name + ' - Talent Pool',
                    RecordTypeId = talentPoolRT,
                    Employer__c = employerId,
                    Pool_Type__c = 'Employer_Interest',
                    IsActive = true,
                    Status = 'In Progress'
                );
                newPools.add(pool);
            }
        }
        
        if (!newPools.isEmpty()) {
            insert newPools;
            for (Campaign pool : newPools) {
                existingPools.put(pool.Employer__c, pool);
            }
        }
        
        return existingPools;
    }
}