@isTest
public class IOSuperAdminAccountTEST {
    @testSetup
    static void testDATA(){
        Xero_Settings_Super_Admin__c XSSA = new Xero_Settings_Super_Admin__c();
        XSSA.url__c = 'https://dev2.straight2voicemail.com.au';
        XSSA.username__c = 'thanhtruong217@gmail.com';
        XSSA.password__c = 'admin12!';
        Insert XSSA;
        
       
    }
    
	@isTest
    static void logoutTEST(){
        
        SingleRequestMock fakeResponse = new SingleRequestMock();
		Test.setMock(HttpCalloutMock.class, fakeResponse);	
        Test.startTest();
        
            IOSuperAdminAccount IOSAA = new IOSuperAdminAccount();
            IOSAA.logout();
        	
        Test.stopTest();
    }
    @isTest
    static void sendRequestTEST(){
        
       	SingleRequestMock fakeResponse = new SingleRequestMock();
        Test.setMock(HttpCalloutMock.class, fakeResponse); 
		
        Test.startTest();
        
            IOSuperAdminAccount IOSAA = new IOSuperAdminAccount();
            IOSAA.username = 'thanhtruong217@gmail.com';
            IOSAA.password = 'admin12!';
        	IOSAA.FullName = 'tempName';
        	IOSAA.avatar = 'av';
            IOSAA.sendRequest();
        	
        Test.stopTest();
    }
}