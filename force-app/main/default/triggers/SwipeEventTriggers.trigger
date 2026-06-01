/**
 * SwipeEventTrigger
 * Handles talent pool membership on swipe right
 */
trigger SwipeEventTriggers on Swipe_Event__c (after insert) {
    
    List<Swipe_Event__c> rightSwipes = new List<Swipe_Event__c>();
    
    for (Swipe_Event__c swipe : Trigger.new) {
        if (swipe.Direction__c == 'Right' && !swipe.Undo_Applied__c) {
            rightSwipes.add(swipe);
        }
    }
    
    if (!rightSwipes.isEmpty()) {
        SwipeEventHandlers.processRightSwipes(rightSwipes);
    }
}