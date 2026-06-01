@IsTest
private class LeadObjTriggerTest
{
    @IsTest
    private static void testTrigger()
    {
  S2V__Countrycode__c cs = new S2V__Countrycode__c();
  cs.Name = 'AU';
  cs.S2V__Country__c = 'AU';
  cs.S2V__Active__c = TRUE;
  insert cs;

  S2V__Countrycode__c cs1 = new S2V__Countrycode__c();
  cs1.Name = 'CA-US';
  cs1.S2V__Country__c = 'CA-US';
  cs1.S2V__Active__c = FALSE;
  insert cs1;

  S2V__Countrycode__c cs2 = new S2V__Countrycode__c();
  cs2.Name = 'NZ';
  cs2.S2V__Country__c = 'NZ';
  cs2.S2V__Active__c = FALSE;
  insert cs2;

List<Contact> listCon = new List<Contact>();
  Contact objCon = new Contact();
  objCon.lastName = 'test';
  objCon.Email = 'd@d.com';
  objCon.S2V__S2VCustomer_Time_Zone__c = 'Australia/NSW';
  objCon.MailingCountry = 'AU';
  objCon.S2V__S2V_Batch_record__c = true;
  objCon.S2V__S2V_Stop_Notifications__c = false;
  Contact objCon1 = new Contact();
  objCon1.lastName = 'test';
  objCon1.Email = 'd@d.com';
  objCon1.S2V__S2VCustomer_Time_Zone__c = 'Australia/NSW';
  objCon1.MailingCountry = 'AU';
  objCon1.S2V__S2V_Batch_record__c = false;
  objCon1.S2V__S2V_Stop_Notifications__c = false;
  objCon1.S2V__S2V_Stop_Notifications_SMS__c = false;
  listCon.add(objCon);
  listCon.add(objCon1);
  insert listCon;
S2V.RecursiveTriggerHandler.isFirstTime  =true; 
 Lead Leadobj = new Lead();
         Leadobj.LastName = 'test';
         Leadobj.Company = 'test';
         Leadobj.S2V__S2VCustomer_Time_Zone__c = 'Australia/NSW';
         insert Leadobj;
    }
}