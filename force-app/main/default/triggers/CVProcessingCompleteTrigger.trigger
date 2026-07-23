trigger CVProcessingCompleteTrigger on CV_Processing_Complete__e (after insert) {
    for (CV_Processing_Complete__e eventRow : Trigger.new) {
        if (String.isNotBlank(eventRow.Contact_Id__c)) {
            System.enqueueJob(new AICVEnhancementJob((Id) eventRow.Contact_Id__c));
        }
    }
}
