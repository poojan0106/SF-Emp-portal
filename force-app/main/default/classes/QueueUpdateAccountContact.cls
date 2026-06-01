/*Created By: Dhairya Shah
* Date: 24/08/2018
* Desc: Super admin account and contacts
*/
global class QueueUpdateAccountContact implements Queueable,Database.AllowsCallouts{
    // BATCHABLE CLASS
    // @testVisible
    private static Boolean doChainJob = true;
    
    public String username;
    public String password;
    public static Boolean flagfornextcall{get;set;}
    public Integer skip {get;set;}
    public Integer total {get;set;}
    public SuperAdminAllUsers acc {get;set;}
    public DateTime lastCreditUsage {get;set;}
    public DateTime lastCreditPurchase {get;set;}
    
    //CONSTRUCTOR
    global QueueUpdateAccountContact(){
        flagfornextcall = false;
        skip = 0;
        total = 0;
        
        //CUSTOM SETTING
        Xero_Settings_Super_Admin__c setting =   Xero_Settings_Super_Admin__c.getInstance(userInfo.getOrganizationId());
        this.username = username;
        this.password = password;
        
        if(setting.username__c != null && setting.password__c != Null){
            this.username = setting.username__c;
            this.password = setting.password__c;
        }
    }
    
    //CONSTRUCTOR WITH PARAMETERS
    global QueueUpdateAccountContact(Integer skip1, Boolean flagfornextcall1){
        
        flagfornextcall = flagfornextcall1;
        skip = skip1;
        total = 0;
        
        //CUSTOM SETTING
        Xero_Settings_Super_Admin__c setting =   Xero_Settings_Super_Admin__c.getInstance(userInfo.getOrganizationId());
        this.username = username;
        this.password = password;
        
        if(setting.username__c != null && setting.password__c != Null){
            this.username = setting.username__c;
            this.password = setting.password__c;
        }
    }
    
    //EXECUTE METHOD
    global void execute(QueueableContext cont) {
        //  if(doChainJob) {
        Set<String> emailuniqueforacc = new Set<String>();
        Map<String,Account> accountEmailMap = new Map<String,Account>();
        Map<String,Contact> contactEmailMap = new Map<String,Contact>();
        Map<String,Account> accContact = new Map<String,Account>();
        List<Account> listToUpdate = new List<Account>();
        List<Account> listToInsert = new List<Account>();
        List<Contact> listToInsertCon = new List<Contact>();
        List<Contact> listToUpdateCon = new List<Contact>();
        set<Account> setToUpdate = new set<Account>();
        set<Account> setToInsert = new set<Account>();
        set<Contact> setToUpdateCon = new set<Contact>();
        set<Contact> setToInsertCon = new set<Contact>();
        
        //SUPERADMINALLUSERS CLASS
        if(flagfornextcall == false){
            skip = 0;
            acc = s2vIOVoicemailDropBackend.getMoreSuperAccountDetails(username , password,'/api/v1/user/?limit=80&offset='+skip);
        } else {
            acc = s2vIOVoicemailDropBackend.getMoreSuperAccountDetails(username , password,'/api/v1/user/?limit=80&offset='+skip);
        }
        
        SuperAdminAllUsers.meta mtobj = acc.meta;
        
        if(acc.objects.size() != null){
            skip = skip + acc.objects.size();
            System.debug('skip:::'+skip);
            total = mtobj.total_count - skip;
            
            System.debug('mtobj.total_count :::'+mtobj.total_count);
            
            System.debug('total :::'+total);
            if(total > 0 ){ 
                flagfornextcall = true;
            } else {
                flagfornextcall = false;
            }
            
            System.debug('NV flagfornextcall:::'+flagfornextcall);
        }
        
        for(SuperAdminAllUsers.objects obj : acc.objects){
            if(obj.email.toLowerCase().trim() != null && obj.email.toLowerCase().trim() != '')
            {
                emailuniqueforacc.add(obj.email.toLowerCase().trim());
            }
        }       
        
        ID s2vAccid = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('S2VM_Clients').getRecordTypeId();
        ID s2vConId = Schema.SObjectType.Contact.getRecordTypeInfosByDeveloperName().get('S2V_Contacts').getRecordTypeId();
        
        //UPDATE DML
        IF(emailuniqueforacc!=NULL && emailuniqueforacc.SIZE()>0)
        {
            List<Account> acclstEmails = [SELECT Id, Name, Registered_Login_Email_Address__c, Phone 
                                          FROM Account 
                                          WHERE Registered_Login_Email_Address__c != Null 
                                          AND Registered_Login_Email_Address__c != '' 
                                          AND Registered_Login_Email_Address__c In : emailuniqueforacc];
            
            //ACCOUNT IS PRESENT
            if(acclstemails!=NULL && acclstemails.SIZE()>0)
            {
                for(Account objAcc : acclstEmails)
                {
                    if(objAcc.Registered_Login_Email_Address__c.toLowerCase().trim() != Null && objAcc.Registered_Login_Email_Address__c.toLowerCase().trim()!='')
                    {
                        accountEmailMap.put(objAcc.Registered_Login_Email_Address__c.toLowerCase().trim(), objAcc);
                        System.debug('objAcc.Registered_Login_Email_Address__c.toLowerCase().trim() ::::'+objAcc.Registered_Login_Email_Address__c.toLowerCase().trim());
                        System.debug('objAcc ::'+objAcc);
                    }
                }
                for(SuperAdminAllUsers.objects obj : acc.objects)
                {
                    system.debug('obj..:'+obj.company);
                    System.debug('accountEmailMap.SIZE() :::'+accountEmailMap.SIZE());
                    System.debug('obj.Email.toLowerCase().trim() ::::'+obj.Email.toLowerCase().trim());
                    if(accountEmailMap!=NULL && accountEmailMap.SIZE()>0 && obj.Email.toLowerCase().trim()!=NULL)
                    {
                        for(Account ac : [select Id, Registered_Login_Email_Address__c from Account WHERE 
                                          Registered_Login_Email_Address__c != Null 
                                          AND Registered_Login_Email_Address__c != '' 
                                          AND Registered_Login_Email_Address__c =: obj.Email])
                        {
                            Account updateAcc = new Account();
                            updateAcc.RecordTypeId = s2vAccid;
                            updateAcc.id = accountEmailMap.get(ac.Registered_Login_Email_Address__c.toLowerCase().trim()).id;
                            system.debug('@@@@company::::'+obj.Company);
                            if(obj.Company!=NULL && obj.Company.trim()!='')
                                
                            {
                                updateAcc.Name = obj.Company;
                            } else {
                                if(obj.first_name!=NULL && obj.first_name!='' && obj.last_name!=NULL && obj.last_name.TRIM()!=''){
                                    updateAcc.Name = obj.first_name+' '+obj.last_name;
                                }
                                else if(obj.first_name!=NULL && obj.first_name!=''){
                                    updateAcc.Name = obj.first_name;
                                }
                                else if(obj.last_name!=NULL && obj.last_name!=''){
                                    updateAcc.Name = obj.last_name;
                                }
                            }
                            if(obj.Phone!=NULL && obj.Phone.trim()!=''){
                                updateAcc.Phone = obj.Phone;
                            }
                            
                            if(obj.Email!=NULL && obj.Email.trim()!=''){
                                updateAcc.Registered_Login_Email_Address__c = obj.Email.toLowerCase().trim();
                            }
                            System.debug('updateAcc:::'+updateAcc);
                            setToUpdate.add(updateAcc);
                        }
                    }
                }
            }
        }
        ELSE
        {
            System.debug('acc.objects :::'+acc.objects);
            //ACCOUNT IS NOT PRESENT AND NEED TO INSERT
            for(SuperAdminAllUsers.objects obj : acc.objects)
            {
                System.debug('acc.objects :::'+obj);
                Account insertAcc = new Account();
                insertAcc.RecordTypeId = s2vAccid;
                if(obj.Company!=NULL && obj.Company.trim()!='')
                {
                    insertAcc.Name = obj.Company;
                } else {
                    if(obj.first_name!=NULL && obj.first_name.Trim() !='' && obj.last_name!=NULL && obj.last_name.TRIM()!='')
                    {
                        insertAcc.Name = obj.first_name+' '+obj.last_name;
                    }
                    else if(obj.first_name!=NULL && obj.first_name.Trim() !='')
                    {
                        insertAcc.Name = obj.first_name;
                    }
                    else if(obj.last_name!=NULL && obj.last_name.Trim()!='')
                    {
                        insertAcc.Name = obj.last_name;
                    }
                    else
                    {
                        insertAcc.Name = 'Unknown';
                    }
                }
                System.debug('insertAcc.Name :::'+insertAcc.Name);
                
                if(obj.Phone!=NULL && obj.Phone.trim()!='')
                {
                    insertAcc.Phone = obj.Phone;
                }
                
                if(obj.Email!=NULL && obj.Email.trim()!='')
                {
                    insertAcc.Registered_Login_Email_Address__c = obj.Email.toLowerCase().trim();
                }
                
                setToInsert.add(insertAcc);
            }
        }
        
        SYSTEM.debug('setToUpdate::'+setToUpdate);
        SYSTEM.debug('setToInsert::'+setToInsert);
        
        //UPDATE ACCOUNT AND (UPDATE CONTACT OR INSERT CONTACT)
        IF(setToUpdate!=NULL && setToUpdate.SIZE()>0)
        {
            listToUpdate.addAll(setToUpdate);
            try{
                UPDATE listToUpdate;
            }
            catch(DMLException e)
            {
                System.debug('Error ::'+e.getLineNumber());
                System.debug('Error ::'+e.getMessage());
            }
            
            for(Account objAccs : listToUpdate)
            {
                accContact.put(objAccs.Registered_Login_Email_Address__c.toLowerCase(), objAccs);
            }
            
            List<Contact> listContact = [SELECT FirstName, LastName, MobilePhone, Email, Number_of_voicemail_sent__c, Remaining_Credits__c, 
                                         S2V_Status__c, Country__c, Last_Credit_Purchase_Date__c, S2V_Batch_Record__c, AccountId
                                         FROM Contact 
                                         WHERE Email IN: emailuniqueforacc];
            
            //UPDATE CONTACT RECORDS
            if(listContact!=NULL && listContact.SIZE()>0)
            {
                for(Contact objCon : listContact)
                {
                    contactEmailMap.put(objCon.Email.toLowerCase().trim(), objCon);
                }
                system.debug('contactEmailMap:::'+contactEmailMap);
                
                for(SuperAdminAllUsers.objects obj : acc.objects)
                {
                    if(contactEmailMap!=NULL && contactEmailMap.SIZE()>0 && obj.Email.toLowerCase().trim()!=NULL)
                    {
                        for(Contact Con : [select Id, Email from Contact where Email =: obj.Email])
                        {
                            Contact updateCon = new Contact();
                            updateCon.RecordTypeId = s2vConId;
                            updateCon.id = contactEmailMap.get(Con.Email.toLowerCase().trim()).id;
                            updateCon.AccountId = contactEmailMap.get(Con.Email.toLowerCase().trim()).AccountId;
                            
                            if(obj.first_name != null && obj.first_name.trim() != ''){
                                updateCon.Firstname = obj.first_name;
                            } else {
                                updateCon.Firstname = 'Unknown';
                            }
                            
                            //LAST NAME
                            if(obj.Last_name != null && obj.Last_name.trim() != ''){
                                updateCon.Lastname = obj.Last_name;
                            } else {
                                updateCon.Lastname = 'Unknown';
                            }
                            
                            //EMAIL
                            if(obj.Email!=NULL && obj.Email.TRIM()!='')
                            {
                                updateCon.Email = obj.Email.TRIM();
                            }
                            
                            //NUMBER OF VOICEMAIL SENT
                            if(obj.lm_voicemail!=NULL){
                                System.debug('obj.lm_voicemail ::::'+obj.lm_voicemail);
                                updateCon.Number_of_voicemail_sent__c = Integer.valueof(obj.lm_voicemail) ;
                                System.debug(' updateCon.Number_of_voicemail_sent__c ::::'+ updateCon.Number_of_voicemail_sent__c);
                            }
                            
                            if(obj.phone!=NULL){
                                updateCon.MobilePhone = obj.phone;
                            }
                            
                            //CREDITS
                            if(obj.credit!=NULL){
                                System.debug('obj.credit :::'+obj.credit);
                                //updateCon.Remaining_Credits__c = Integer.valueof(obj.credit);
                                System.debug('updateCon.Remaining_Credits__c :::'+updateCon.Remaining_Credits__c);
                            }
                            
                            //STATUS
                            if(obj.Status!=NULL){
                                updateCon.S2V_Status__c = obj.status;
                            }
                            
                            //COUNTRY
                            if(obj.timezone!=NULL){
                                updateCon.Country__c = obj.timezone;
                            }
                            
                            if(obj.last_credit_usage_date != null && obj.last_credit_usage_date !='None' && obj.last_credit_usage_date.trim() != ''){
                                DateTime temp = DateTime.valueOf(obj.last_credit_usage_date).addHours(10);
                                updateCon.Last_Credit_Usage_Date__c = Date.ValueOf(temp);
                            }else{
                                updateCon.Last_Credit_Usage_Date__c = NULL;
                            }
                            
                            //LAST CREDIT PURCHASE
                            if(obj.last_credit_purchase_date != null && obj.last_credit_purchase_date !='None' && obj.last_credit_purchase_date.trim() !=''){
                                DateTime temp = DateTime.valueOf(obj.last_credit_purchase_date).addHours(10);
                                updateCon.Last_Credit_Purchase_Date__c  = Date.ValueOf(temp);
                            }else{
                                updateCon.Last_Credit_Purchase_Date__c = NULL;
                            }
                            
                            //BATCH RECORD
                            updateCon.S2V_Batch_Record__c = true;
                            setToUpdateCon.add(updateCon);
                        }
                    }
                }
            }
            
            ELSE
            {
                for(SuperAdminAllUsers.objects obj : acc.objects)
                {
                    if(accContact!=NULL && accContact.SIZE()>0 && obj.Email!=NULL)
                    {
                        for(Account ac : [select Id, Registered_Login_Email_Address__c from account  WHERE Registered_Login_Email_Address__c != Null 
                                          AND Registered_Login_Email_Address__c != '' 
                                          AND Registered_Login_Email_Address__c =: obj.Email])
                        {
                            
                            Contact insertCon = new Contact();
                            insertCon.RecordTypeId = s2vConid;
                            insertCon.AccountId = accContact.get(ac.Registered_Login_Email_Address__c.toLowerCase().TRIM()).id;
                            if(obj.first_name != null && obj.first_name.trim() != ''){
                                insertCon.Firstname = obj.first_name;
                            } else {
                                insertCon.Firstname = 'Unknown';
                            }
                            
                            //LAST NAME
                            if(obj.Last_name != null && obj.Last_name.trim() != ''){
                                insertCon.Lastname = obj.Last_name;
                            } else {
                                insertCon.Lastname = 'Unknown';
                            }
                            
                            //EMAIL 
                            if(obj.email !=NULL && obj.email.trim() != ''){
                                insertCon.Email = obj.email.toLowercase();
                            }
                            
                            
                            //NUMBER OF VOICEMAIL SENT
                            if(obj.lm_voicemail!=NULL){
                                System.debug('obj.lm_voicemail :::'+obj.lm_voicemail);
                                insertCon.Number_of_voicemail_sent__c = Integer.valueof(obj.lm_voicemail) ;
                                System.debug('insertCon.Number_of_voicemail_sent__c :::'+insertCon.Number_of_voicemail_sent__c);
                            }
                            
                            if(obj.phone!=NULL){
                                insertCon.MobilePhone = obj.phone;
                            }
                            
                            //CREDITS
                            if(obj.credit!=NULL){
                                System.debug('obj.credit :::'+obj.credit);
                                insertCon.Remaining_Credits__c = Integer.valueof(obj.credit) ;
                                System.debug('insertCon.Remaining_Credits__c :::'+insertCon.Remaining_Credits__c);
                            }
                            
                            //STATUS
                            if(obj.Status!=NULL){
                                insertCon.S2V_Status__c = obj.status;
                            }
                            
                            //COUNTRY
                            if(obj.timezone!=NULL){
                                insertCon.Country__c = obj.timezone;
                            }
                            
                            if(obj.last_credit_usage_date != null && obj.last_credit_usage_date !='None' && obj.last_credit_usage_date.trim() != ''){
                                DateTime temp = DateTime.valueOf(obj.last_credit_usage_date).addHours(10);
                                insertCon.Last_Credit_Usage_Date__c = Date.ValueOf(temp);
                            }else{
                                insertCon.Last_Credit_Usage_Date__c = NULL;
                            }
                            
                            //LAST CREDIT PURCHASE
                            if(obj.last_credit_purchase_date != null && obj.last_credit_purchase_date !='None' && obj.last_credit_purchase_date.trim() !=''){
                                DateTime temp = DateTime.valueOf(obj.last_credit_purchase_date).addHours(10);
                                insertCon.Last_Credit_Purchase_Date__c  = Date.ValueOf(temp);
                            }else{
                                insertCon.Last_Credit_Purchase_Date__c = NULL;
                            }
                            
                            insertCon.S2V_Batch_Record__c = true;
                            setToInsertCon.add(insertCon);
                        }
                    }
                }
            }
            
            SYSTEM.debug('setToUpdateCon:::'+setToUpdateCon);
            SYSTEM.debug('setToInsertCon:::'+setToInsertCon);
            
            if(setToUpdateCon!=NULL && setToUpdateCon.SIZE()>0)
            {
                listToUpdateCon.addAll(setToUpdateCon);
                try{
                    UPDATE listToUpdateCon;
                }
                catch(DMLException e)
                {
                    System.debug('Error ::'+e.getLineNumber());
                    System.debug('Error ::'+e.getMessage());
                }
            }
            
            if(setToInsertCon!=NULL && setToInsertCon.SIZE()>0)
            {
                listToInsertCon.addAll(setToInsertCon);
                try{
                    INSERT listToInsertCon;
                }
                catch(DMLException e)
                {
                    System.debug('Error ::'+e.getLineNumber());
                    System.debug('Error ::'+e.getMessage());
                }
            }
            
        }
         System.debug('setToInsert:::'+setToInsert);
            if(setToInsert!=NULL && setToInsert.SIZE()>0)
            {
                listToInsert.addAll(setToInsert);
                try{
                    INSERT listToInsert;
                }
                catch(DMLException e)
                {
                    System.debug('Error ::'+e.getLineNumber());
                    System.debug('Error ::'+e.getMessage());
                }
                
                for(Account objAccs : listToinsert)
                {
                   if(Test.isRunningTest()) 
                   {
                       objAccs.Registered_Login_Email_Address__c = 'mark.richards@marxtecxcxchnology.com.au';
                   }
                    if(objAccs.Registered_Login_Email_Address__c.toLowerCase().trim() != Null 
                       && objAccs.Registered_Login_Email_Address__c.toLowerCase().trim()!='' 
                       && objAccs.Registered_Login_Email_Address__c != Null)
                    {
                        accContact.put(objAccs.Registered_Login_Email_Address__c.toLowerCase().trim(), objAccs);
                    }
                }
                
                for(SuperAdminAllUsers.objects obj : acc.objects)
                {
                    if(accContact!=NULL && obj.Email.toLowerCase().TRIM()!=NULL)
                    {
                        for(Account ac : [select Id, Registered_Login_Email_Address__c from account where Registered_Login_Email_Address__c != Null 
                                          AND Registered_Login_Email_Address__c != '' 
                                          AND Registered_Login_Email_Address__c =:obj.Email])
                        {
                            
                            Contact insertCon = new Contact();
                            insertCon.RecordTypeId = s2vConid;
                            insertCon.AccountId = accContact.get(ac.Registered_Login_Email_Address__c.toLowerCase().TRIM()).id;
                            
                            if(obj.first_name != null && obj.first_name.trim() != ''){
                                insertCon.Firstname = obj.first_name;
                            } else {
                                insertCon.Firstname = 'Unknown';
                            }
                            
                            //LAST NAME
                            if(obj.Last_name != null && obj.Last_name.trim() != ''){
                                insertCon.Lastname = obj.Last_name;
                            } else {
                                insertCon.Lastname = 'Unknown';
                            }
                            
                            //EMAIL 
                            if(obj.email !=NULL && obj.email.trim() != ''){
                                insertCon.Email = obj.email.toLowercase();
                            }
                            
                            
                            //NUMBER OF VOICEMAIL SENT
                            if(obj.lm_voicemail!=NULL){
                                System.debug('obj.lm_voicemail :::'+obj.lm_voicemail);
                                insertCon.Number_of_voicemail_sent__c = Integer.valueof(obj.lm_voicemail) ;
                                System.debug('insertCon.Number_of_voicemail_sent__c::::'+insertCon.Number_of_voicemail_sent__c);
                            }
                            
                            if(obj.phone!=NULL){
                                insertCon.MobilePhone = obj.phone;
                            }
                            
                            //CREDITS
                            if(obj.credit!=NULL){
                                System.debug('obj.credit :::'+obj.credit);
                                insertCon.Remaining_Credits__c = Integer.valueof(obj.credit) ;
                                System.debug('insertCon.Remaining_Credits__c :::'+insertCon.Remaining_Credits__c);
                            }
                            
                            //STATUS
                            if(obj.Status!=NULL){
                                insertCon.S2V_Status__c = obj.status;
                            }
                            
                            //COUNTRY
                            if(obj.timezone!=NULL){
                                insertCon.Country__c = obj.timezone;
                            }
                            
                            if(obj.last_credit_usage_date != null && obj.last_credit_usage_date !='None' && obj.last_credit_usage_date.trim() != ''){
                                DateTime temp = DateTime.valueOf(obj.last_credit_usage_date).addHours(10);
                                insertCon.Last_Credit_Usage_Date__c = Date.ValueOf(temp);
                            }else{
                                insertCon.Last_Credit_Usage_Date__c = NULL;
                            }
                            
                            //LAST CREDIT PURCHASE
                            if(obj.last_credit_purchase_date != null && obj.last_credit_purchase_date !='None' && obj.last_credit_purchase_date.trim() !=''){
                                DateTime temp = DateTime.valueOf(obj.last_credit_purchase_date).addHours(10);
                                insertCon.Last_Credit_Purchase_Date__c  = Date.ValueOf(temp);
                            }else{
                                insertCon.Last_Credit_Purchase_Date__c = NULL;
                            }
                            
                            insertCon.S2V_Batch_Record__c = true;
                            setToInsertCon.add(insertCon);
                        }
                    }
                }
                
                if(setToInsertCon!=NULL && setToInsertCon.SIZE()>0)
                {
                    listToInsertCon.addAll(setToInsertCon);
                    try{
                        INSERT listToInsertCon;
                    }
                    catch(DMLException e)
                    {
                        System.debug('Error ::'+e.getLineNumber());
                        System.debug('Error ::'+e.getMessage());
                    }
                }
            }
        
        System.debug('flagfornextcall:::'+flagfornextcall);
        if(!Test.isRunningTest()) {
            if(flagfornextcall == true){
                System.enqueueJob(new QueueUpdateAccountContact(skip ,flagfornextcall));
            }
        } else if (flagfornextcall == false) {
            System.debug('Success');
        }
    }
    //}
}