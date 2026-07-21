/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 2: SwipeEventHandler.cls
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Handler class containing all swipe trigger business logic
 * 
 * TASKS COVERED:
 *   - US-041-BE-015: Build SwipeEventHandler.cls
 *   - US-041-BE-022: Update Contact swipe statistics
 * 
 * RESPONSIBILITIES:
 *   - Update candidate statistics (Total_Swipes__c, etc.)
 *   - Trigger talent pool addition for right swipes
 *   - Recalculate statistics on undo
 * ═══════════════════════════════════════════════════════════════════════════
 */
public with sharing class SwipeEventHandler {
    
    /**
     * Handles after insert of swipe events.
     * 
     * ACTIONS:
     * 1. Collect candidate IDs and separate right swipes
     * 2. Update candidate statistics (increment counters)
     * 3. Add right-swiped candidates to talent pools
     * 
     * @param newSwipes List of newly inserted Swipe_Event__c records
     */
    public static void handleAfterInsert(List<Swipe_Event__c> newSwipes) {
        // Collect data for processing
        Set<Id> candidateIds = new Set<Id>();
        List<Swipe_Event__c> rightSwipes = new List<Swipe_Event__c>();
        
        for (Swipe_Event__c swipe : newSwipes) {
            candidateIds.add(swipe.Candidate__c);
            
            // Separate right swipes for talent pool processing
            if (swipe.Direction__c == 'Right') {
                rightSwipes.add(swipe);
            }
        }
        
        // TASK US-041-BE-022: Update Contact swipe statistics
        updateCandidateStatistics(candidateIds, newSwipes);
        
        // Add right-swiped candidates to employer Talent League.
        // Uses story object structure: Talent_League__c + League_Membership__c.
        if (!rightSwipes.isEmpty()) {
            LeagueMembershipService.addRightSwipesToLeague(rightSwipes);
        }
    }
    
    /**
     * Handles after update of swipe events.
     * Primary use case: Detecting undo operations.
     * 
     * ACTIONS:
     * 1. Detect swipes that were just undone (Is_Undone__c changed to true)
     * 2. Recalculate candidate statistics (full recalc needed)
     * 
     * @param newSwipes List of updated Swipe_Event__c records
     * @param oldMap Map of old values before update
     */
    public static void handleAfterUpdate(
        List<Swipe_Event__c> newSwipes, 
        Map<Id, Swipe_Event__c> oldMap
    ) {
        Set<Id> candidateIdsToRecalc = new Set<Id>();
        
        for (Swipe_Event__c swipe : newSwipes) {
            Swipe_Event__c oldSwipe = oldMap.get(swipe.Id);
            
            // Detect undo: Is_Undone__c changed from false to true
            if (swipe.Is_Undone__c == true && oldSwipe.Is_Undone__c == false) {
                candidateIdsToRecalc.add(swipe.Candidate__c);
            }
        }
        
        // Recalculate statistics for affected candidates
        if (!candidateIdsToRecalc.isEmpty()) {
            recalculateCandidateStatistics(candidateIdsToRecalc);
        }
    }
    
    /**
     * TASK US-041-BE-022: Updates Contact swipe statistics after new swipes.
     * 
     * INCREMENTS:
     *   - Total_Swipes__c: +1 for each swipe
     *   - Total_Right_Swipes__c: +1 for right swipes
     *   - Total_Left_Swipes__c: +1 for left swipes
     *   - Last_Swipe_Date__c: Set to now
     * 
     * @param candidateIds Set of Contact IDs to update
     * @param swipes List of swipe events to count
     */
    private static void updateCandidateStatistics(
        Set<Id> candidateIds, 
        List<Swipe_Event__c> swipes
    ) {
        // Build increment maps per candidate
        Map<Id, Integer> totalIncrements = new Map<Id, Integer>();
        Map<Id, Integer> rightIncrements = new Map<Id, Integer>();
        Map<Id, Integer> leftIncrements = new Map<Id, Integer>();
        
        for (Swipe_Event__c swipe : swipes) {
            Id candId = swipe.Candidate__c;
            
            // Increment total
            Integer current = totalIncrements.get(candId);
            totalIncrements.put(candId, (current == null ? 0 : current) + 1);
            
            // Increment direction-specific counter
            if (swipe.Direction__c == 'Right') {
                current = rightIncrements.get(candId);
                rightIncrements.put(candId, (current == null ? 0 : current) + 1);
            } else if (swipe.Direction__c == 'Left') {
                current = leftIncrements.get(candId);
                leftIncrements.put(candId, (current == null ? 0 : current) + 1);
            }
        }
        
        // Query existing contacts
        List<Contact> contactsToUpdate = [
            SELECT Id, Total_Swipes__c, Total_Right_Swipes__c, Total_Left_Swipes__c
            FROM Contact
            WHERE Id IN :candidateIds
        ];
        
        // Apply increments
        for (Contact c : contactsToUpdate) {
            // Total swipes
            if (totalIncrements.containsKey(c.Id)) {
                c.Total_Swipes__c = nullSafeAdd(c.Total_Swipes__c, totalIncrements.get(c.Id));
            }
            
            // Right swipes
            if (rightIncrements.containsKey(c.Id)) {
                c.Total_Right_Swipes__c = nullSafeAdd(c.Total_Right_Swipes__c, rightIncrements.get(c.Id));
            }
            
            // Left swipes
            if (leftIncrements.containsKey(c.Id)) {
                c.Total_Left_Swipes__c = nullSafeAdd(c.Total_Left_Swipes__c, leftIncrements.get(c.Id));
            }
            
            // Update last swipe date
            c.Last_Swipe_Date__c = DateTime.now();
        }
        
        // Save changes
        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }
    
    /**
     * Recalculates candidate statistics from scratch.
     * Used when swipes are undone, as we need accurate counts.
     * 
     * Uses aggregate query for efficiency.
     * 
     * @param candidateIds Set of Contact IDs to recalculate
     */
    private static void recalculateCandidateStatistics(Set<Id> candidateIds) {
        // Use aggregate query to get accurate counts
        // Only count non-undone swipes
        Map<Id, AggregateResult> swipeStats = new Map<Id, AggregateResult>();
        
        for (AggregateResult ar : [
            SELECT 
                Candidate__c,
                COUNT(Id) totalCount,
                MAX(Timestamp__c) lastSwipe
            FROM Swipe_Event__c
            WHERE Candidate__c IN :candidateIds
            AND Is_Undone__c = false
            GROUP BY Candidate__c
        ]) {
            swipeStats.put((Id)ar.get('Candidate__c'), ar);
        }
        
        // Get direction-specific counts separately
        // (Salesforce doesn't support conditional aggregates directly)
        Map<Id, Integer> rightCounts = new Map<Id, Integer>();
        Map<Id, Integer> leftCounts = new Map<Id, Integer>();
        
        for (AggregateResult ar : [
            SELECT 
                Candidate__c,
                Direction__c,
                COUNT(Id) cnt
            FROM Swipe_Event__c
            WHERE Candidate__c IN :candidateIds
            AND Is_Undone__c = false
            GROUP BY Candidate__c, Direction__c
        ]) {
            Id candId = (Id)ar.get('Candidate__c');
            String direction = (String)ar.get('Direction__c');
            Integer count = (Integer)ar.get('cnt');
            
            if (direction == 'Right') {
                rightCounts.put(candId, count);
            } else if (direction == 'Left') {
                leftCounts.put(candId, count);
            }
        }
        
        // Build contact updates
        List<Contact> contactsToUpdate = new List<Contact>();
        
        for (Id candidateId : candidateIds) {
            Contact c = new Contact(Id = candidateId);
            
            if (swipeStats.containsKey(candidateId)) {
                AggregateResult ar = swipeStats.get(candidateId);
                c.Total_Swipes__c = (Decimal) ar.get('totalCount');
                c.Last_Swipe_Date__c = (DateTime) ar.get('lastSwipe');
            } else {
                // No swipes remain
                c.Total_Swipes__c = 0;
                c.Last_Swipe_Date__c = null;
            }
            
            // Set direction counts
            c.Total_Right_Swipes__c = rightCounts.containsKey(candidateId) 
                                      ? rightCounts.get(candidateId) 
                                      : 0;
            c.Total_Left_Swipes__c = leftCounts.containsKey(candidateId) 
                                     ? leftCounts.get(candidateId) 
                                     : 0;
            
            contactsToUpdate.add(c);
        }
        
        // Save changes
        if (!contactsToUpdate.isEmpty()) {
            update contactsToUpdate;
        }
    }
    
    /**
     * Helper: Adds value to possibly-null decimal.
     */
    private static Decimal nullSafeAdd(Decimal current, Integer increment) {
        return (current == null ? 0 : current) + increment;
    }
}
