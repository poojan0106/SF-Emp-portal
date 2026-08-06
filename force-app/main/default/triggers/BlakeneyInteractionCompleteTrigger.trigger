trigger BlakeneyInteractionCompleteTrigger on Blakeney_Interaction_Complete__e (after insert) {
    for (Blakeney_Interaction_Complete__e eventRow : Trigger.New) {
        System.enqueueJob(new BlakeneyInteractionEnrichmentJob(
            eventRow.Contact_Id__c,
            eventRow.Interaction_Type__c,
            eventRow.Updated_Fields__c,
            eventRow.Career_Intent_Id__c,
            eventRow.Career_Constraints_Id__c,
            eventRow.Session_Id__c
        ));
    }
}