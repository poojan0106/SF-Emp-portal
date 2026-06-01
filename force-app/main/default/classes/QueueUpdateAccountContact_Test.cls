@isTest
private class QueueUpdateAccountContact_Test{
    static testMethod void test_execute_UseCase1(){
        
        Integer limitofdata = 10;
        boolean flag = true;
        
        DateTime lastCreditUsage= datetime.newInstance(2014, 9, 15, 12, 30, 0);
        
        
        //CUSTOM SETTING INSERTION
        List<Xero_Settings_Super_Admin__c> listSetting = new List<Xero_Settings_Super_Admin__c>();
        Xero_Settings_Super_Admin__c setting = new Xero_Settings_Super_Admin__c();
        setting.username__c = 'test';
        setting.password__c = 'test';
        listSetting.add(setting);
        insert listSetting;
        
        S2V_Trigger_Handler__c objCS = new S2V_Trigger_Handler__c ();
        objCS.Name = 'TriggerHandler';
        objCS.S2VTimeZoneContact__c =  TRUE;
        objCS.S2VTimeZoneLead__c = true;
        objCS.S2VTimeZoneOpp__c = true;
        insert objCS;
        
        S2V__S2V_Trigger_Handler__c objSCS = new S2V__S2V_Trigger_Handler__c();
        objSCS.Name = 'TriggerHandler';
        objSCS.S2V__S2VTimeZoneContact__c = true;
        insert objSCS;
        
        Account objAc = new Account();
        objAc.Name = 'Testing';
        objAc.Registered_Login_Email_Address__c = 'mark.richards@marxtecxcxchnology.com.au';
        
        insert objAc;
        
        Contact objC = new Contact();
        objC.FirstName = 'Unknown';
        objC.lastName = 'Unknown';
        objC.AccountId = objAc.id;
        objC.Email = objAC.Registered_Login_Email_Address__c;
        insert objC;
        
        
        //CREATING FAKE RESPONSE
        SingleRequestMock fakeResponse = new SingleRequestMock();
        Test.setMock(HttpCalloutMock.class, fakeResponse); 
        
        Test.startTest();  
        System.enqueueJob(new QueueUpdateAccountContact());
        QueueUpdateAccountContact objQu = new QueueUpdateAccountContact(1, true);
        
        Test.stopTest();
    }
    static testMethod void test_execute_UseCase2(){
        
        Integer limitofdata = 10;
        boolean flag = true;
        
        DateTime lastCreditUsage= datetime.newInstance(2014, 9, 15, 12, 30, 0);
        
        
        //CUSTOM SETTING INSERTION
        List<Xero_Settings_Super_Admin__c> listSetting = new List<Xero_Settings_Super_Admin__c>();
        Xero_Settings_Super_Admin__c setting = new Xero_Settings_Super_Admin__c();
        setting.username__c = 'test';
        setting.password__c = 'test';
        listSetting.add(setting);
        insert listSetting;
        
        S2V_Trigger_Handler__c objCS = new S2V_Trigger_Handler__c ();
        objCS.Name = 'TriggerHandler';
        objCS.S2VTimeZoneContact__c =  TRUE;
        objCS.S2VTimeZoneLead__c = true;
        objCS.S2VTimeZoneOpp__c = true;
        insert objCS;
        
        S2V__S2V_Trigger_Handler__c objSCS = new S2V__S2V_Trigger_Handler__c();
        objSCS.Name = 'TriggerHandler';
        objSCS.S2V__S2VTimeZoneContact__c = true;
        insert objSCS;
        
        Account objAc = new Account();
        objAc.Name = 'Testing';
        objAc.Registered_Login_Email_Address__c = 'mark.richards@marxtecxcxchnology.com.au';
        objAc.Phone='3579412586';
        insert objAc;
        
        //CREATING FAKE RESPONSE
        SingleRequestMock fakeResponse = new SingleRequestMock();
        Test.setMock(HttpCalloutMock.class, fakeResponse); 
        
        Test.startTest();  
        System.enqueueJob(new QueueUpdateAccountContact());
        QueueUpdateAccountContact objQu = new QueueUpdateAccountContact(1, true);
        
        Test.stopTest();
    }
    
    static testMethod void test_execute_UseCase3(){
        
        Integer limitofdata = 10;
        boolean flag = true;
        
        DateTime lastCreditUsage= datetime.newInstance(2014, 9, 15, 12, 30, 0);
        
        
        //CUSTOM SETTING INSERTION
        List<Xero_Settings_Super_Admin__c> listSetting = new List<Xero_Settings_Super_Admin__c>();
        Xero_Settings_Super_Admin__c setting = new Xero_Settings_Super_Admin__c();
        setting.username__c = 'test';
        setting.password__c = 'test';
        listSetting.add(setting);
        insert listSetting;
        
        S2V_Trigger_Handler__c objCS = new S2V_Trigger_Handler__c ();
        objCS.Name = 'TriggerHandler';
        objCS.S2VTimeZoneContact__c =  TRUE;
        objCS.S2VTimeZoneLead__c = true;
        objCS.S2VTimeZoneOpp__c = true;
        insert objCS;
        
        S2V__S2V_Trigger_Handler__c objSCS = new S2V__S2V_Trigger_Handler__c();
        objSCS.Name = 'TriggerHandler';
        objSCS.S2V__S2VTimeZoneContact__c = true;
        insert objSCS;
        
        Account objAc = new Account();
        objAc.Name = 'Testing';
        objAc.Registered_Login_Email_Address__c = 'mark.richards@marxtecxcxchnology.com.au';
        objAc.Phone='3579412586';
        insert objAc;
        
        Contact cont = new contact();
        cont.FirstName = 'hello';
        cont.LastName = 'world';
        cont.AccountId = objAc.id;
        cont.Email = 'mark.richards@marxtecxcxchnology.com.au';
        insert cont;
        
        //CREATING FAKE RESPONSE
        SingleRequestMock2 fakeResponse = new SingleRequestMock2();
        Test.setMock(HttpCalloutMock.class, fakeResponse); 
        
        Test.startTest();  
        System.enqueueJob(new QueueUpdateAccountContact());
        QueueUpdateAccountContact objQu = new QueueUpdateAccountContact(1, true);
        
        Test.stopTest();
    }    
    static testMethod void test_execute_UseCase4(){
        
        Integer limitofdata = 10;
        boolean flag = true;
        
        DateTime lastCreditUsage= datetime.newInstance(2014, 9, 15, 12, 30, 0);
        
        
        //CUSTOM SETTING INSERTION
        List<Xero_Settings_Super_Admin__c> listSetting = new List<Xero_Settings_Super_Admin__c>();
        Xero_Settings_Super_Admin__c setting = new Xero_Settings_Super_Admin__c();
        setting.username__c = 'test';
        setting.password__c = 'test';
        listSetting.add(setting);
        insert listSetting;
        
        S2V_Trigger_Handler__c objCS = new S2V_Trigger_Handler__c ();
        objCS.Name = 'TriggerHandler';
        objCS.S2VTimeZoneContact__c =  TRUE;
        objCS.S2VTimeZoneLead__c = true;
        objCS.S2VTimeZoneOpp__c = true;
        insert objCS;
        
        S2V__S2V_Trigger_Handler__c objSCS = new S2V__S2V_Trigger_Handler__c();
        objSCS.Name = 'TriggerHandler';
        objSCS.S2V__S2VTimeZoneContact__c = true;
        insert objSCS;
        
   
        //CREATING FAKE RESPONSE
        SingleRequestMock fakeResponse = new SingleRequestMock();
        Test.setMock(HttpCalloutMock.class, fakeResponse); 
        
        Test.startTest();  
        System.enqueueJob(new QueueUpdateAccountContact());
        QueueUpdateAccountContact objQu = new QueueUpdateAccountContact(1, false);
        
        Test.stopTest();
    }
}