trigger TaskObjTrigger on Task (after insert, after update)
{
    Boolean voicemail = true;
	Boolean isValid = false;
	Boolean isNotBatchRecord = false;
	Boolean StopNotification = false;
   System.debug(S2V.RecursiveTriggerHandler.isFirstTime);
   if(S2V.RecursiveTriggerHandler.canIRun() && !system.isBatch() && !system.isFuture()){
       S2V.RecursiveTriggerHandler.isFirstTime = false;
    	String selectedObject = 'Task';
    	String selectedFieldType = 'Contact'; 
   	List<Id> listOfRecIds = new List<Id>();
		Set<String> customerTimezone = new set<String>();
       for(Task objTask : Trigger.new){
      	if(objTask.S2V__S2VCustomer_Time_Zone__c!=NULL && objTask.S2V__S2V_Stop_Notifications__c == FALSE){
 				StopNotification = objTask.S2V__S2V_Stop_Notifications__c;
               customerTimezone.add(objTask.S2V__S2VCustomer_Time_Zone__c);
               isNotBatchRecord = S2V.S2VTimezonevalidation.isItBatchContact(selectedObject, objTask);
				listOfRecIds.add(objTask.id);
			 }
       }  

       if(customerTimezone!=NULL && customerTimezone.SIZE()>0 && !customerTimezone.isEmpty()){
			 Boolean isValid = S2V.S2VTimezonevalidation.isValidForSendVM1(customerTimezone);
             if((isValid == true || isValid == false) && isNotBatchRecord == true && voicemail == true && stopNotification == false && listOfRecIds!=NULL){
				FOR(String customerTime : customerTimeZone){
					S2V.S2VTimezonevalidation.insertFutureVoicemails('Task',true,listOfRecIds,'Contact','WhoId',customerTime);
		  }
		}
	 }
  }
}