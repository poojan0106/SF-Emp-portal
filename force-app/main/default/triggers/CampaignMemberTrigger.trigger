/**
 * ═══════════════════════════════════════════════════════════════════════════
 * FILE 1: CampaignMemberTrigger.trigger
 * ═══════════════════════════════════════════════════════════════════════════
 * 
 * PURPOSE: Trigger to update Campaign metrics when members change
 * 
 * TASK COVERED: US-045-BE-023
 * 
 * EVENTS HANDLED:
 *   - After Insert: New member added to pool
 *   - After Update: Member status changed
 *   - After Delete: Member removed from pool
 *   - After Undelete: Member restored
 * ═══════════════════════════════════════════════════════════════════════════
 */
trigger CampaignMemberTrigger on CampaignMember (
    after insert, 
    after update, 
    after delete, 
    after undelete
) {
    // Delegate to handler class
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            CampaignMemberHandler.handleAfterInsert(Trigger.new);
        }
        if (Trigger.isUpdate) {
            CampaignMemberHandler.handleAfterUpdate(Trigger.new, Trigger.oldMap);
        }
        if (Trigger.isDelete) {
            CampaignMemberHandler.handleAfterDelete(Trigger.old);
        }
        if (Trigger.isUndelete) {
            CampaignMemberHandler.handleAfterUndelete(Trigger.new);
        }
    }
}