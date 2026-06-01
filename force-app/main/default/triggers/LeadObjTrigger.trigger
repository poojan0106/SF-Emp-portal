trigger LeadObjTrigger on Lead (after insert, after update)
{
    Boolean voicemail = true;
	Boolean isValid = false;
	Boolean isNotBatchRecord = false;
	Boolean StopNotification = false;
   System.debug(S2V.RecursiveTriggerHandler.isFirstTime);
   if(S2V.RecursiveTriggerHandler.canIRun() && !system.isBatch() && !system.isFuture()){
       S2V.RecursiveTriggerHandler.isFirstTime = false;
    	String selectedObject = 'Lead';
    	String selectedFieldType = 'null'; 
   	List<Id> listOfRecIds = new List<Id>();
		Set<String> customerTimezone = new set<String>();
       for(Lead objLead : Trigger.new){
      	if(objLead.S2V__S2VCustomer_Time_Zone__c!=NULL && objLead.S2V__S2V_Stop_Notifications__c == FALSE){
 				StopNotification = objLead.S2V__S2V_Stop_Notifications__c;
               customerTimezone.add(objLead.S2V__S2VCustomer_Time_Zone__c);
               isNotBatchRecord = S2V.S2VTimezonevalidation.isItBatchContact(selectedObject, objLead);
				listOfRecIds.add(objLead.id);
			 }
       }  

       if(customerTimezone!=NULL && customerTimezone.SIZE()>0 && !customerTimezone.isEmpty()){
			 Boolean isValid = S2V.S2VTimezonevalidation.isValidForSendVM1(customerTimezone);
             if((isValid == true || isValid == false) && isNotBatchRecord == true && voicemail == true && stopNotification == false && listOfRecIds!=NULL){
				FOR(String customerTime : customerTimeZone){
					S2V.S2VTimezonevalidation.insertFutureVoicemails('Lead',true,listOfRecIds,'null','null',customerTime);
		  }
		}
	 }
  }
}