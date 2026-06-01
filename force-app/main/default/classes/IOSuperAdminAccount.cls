/* Created By: Dhairya Shah
 * Date: 24/08/2018
 * Desc: Creating data in custom setting.
 */

public  with sharing class IOSuperAdminAccount{
    
    public String username {get; set;}
    public String FullName {get;set;}
    public String password {get; set;}
    public String avatar {get; set;} 
    public boolean loginFlag {get; set;}
    //public String signupUrl {get;set;}
    public SuperAdminAllUsers acc {get; set;}
    public string email {get;set;}
    
    //CONSTRUCTOR
    public IOSuperAdminAccount(){
        loginFlag = false;
        Xero_Settings_Super_Admin__c  setting =  Xero_Settings_Super_Admin__c.getInstance(userInfo.getOrganizationId());
        email = setting.username__c;
        loginFlag=setting.password__c != null && setting.username__c != null;
        if(loginFlag == true){ 
            acc = s2vIOVoicemailDropBackend.getSuperAccountDetails(setting.username__c, setting.password__c);
            System.debug(acc);
        }
    }
    
    //LOGOUT METHOD
    public void logout(){
        Xero_Settings_Super_Admin__c setting =   Xero_Settings_Super_Admin__c.getInstance(userInfo.getOrganizationId());
        setting.username__c='';
        setting.password__c='';
        update setting;
        loginFlag = false; 
    }
    
    //SEND REQUEST
    public void sendRequest(){ 
        
       	system.debug('in the send request');
        try{
            acc = s2vIOVoicemailDropBackend.getSuperAccountDetails(username, password);
            System.debug(username+' '+password);
            System.debug('-----acc :::'+acc);
            SuperAdminAllUsers.meta mtobj = acc.meta;
            
            Integer limitofdata = mtobj.limit_Z;
            integer Totalcount = mtobj.total_count;
            
            if(s2vIOVoicemailDropBackend.statuscode == 200){
                //FutureClasssynccontacts.callQueueableClassSync(username,password,limitofdata ,Totalcount);
                loginFlag = true;
            } else {
                System.debug('in else');
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.WARNING,'Username or Password might be invalid.'));
            }
            
            for(SuperAdminAllUsers.objects obj : acc.objects){
                System.debug(obj);
            }
            
            //CUSTOM SETTING FOR XERO SETTING SUPER ADMIN
            Xero_Settings_Super_Admin__c setting = Xero_Settings_Super_Admin__c.getInstance(userInfo.getOrganizationId());
            setting.username__c=username;
            setting.password__c=password;
            email = setting.username__c;
            system.debug('setting:::::::'+setting);
            update setting;
            }
        
            Catch(Exception e){
                ApexPages.addmessage(new ApexPages.message(ApexPages.severity.WARNING,'Username or Password might be invalid.'));
            } 
        }
}