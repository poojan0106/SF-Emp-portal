/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 1: SwipeEventTrigger.trigger
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Trigger on Swipe_Event__c to execute business logic
 * 
 * TASK COVERED: US-041-BE-014
 * 
 * EVENTS HANDLED:
 *   - After Insert: Update stats, add to talent pool
 *   - After Update: Handle undo operations
 * ═══════════════════════════════════════════════════════════════════════════
 */
trigger SwipeEventTrigger on Swipe_Event__c (after insert, after update) {
    
    // Delegate to handler class for all logic
    // This keeps the trigger thin and testable
    
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            SwipeEventHandler.handleAfterInsert(Trigger.new);
        }
        
        if (Trigger.isUpdate) {
            SwipeEventHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}