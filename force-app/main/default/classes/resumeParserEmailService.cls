/**
 * @description Email Service that receives resumes and automatically parses them using Claude AI
 * @author Your Name
 * @date 2026-01-08
 */
global class resumeParserEmailService implements Messaging.InboundEmailHandler {
    
    private static final String CLAUDE_MODEL = 'claude-sonnet-4-20250514';
    private static final String CLAUDE_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private static final String CLAUDE_API_KEY = System.Label.Claude_API_Key;
    
    global Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email, 
        Messaging.InboundEnvelope envelope
    ) {
        
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        
        try {
            System.debug('========== RESUME PARSER EMAIL SERVICE ==========');
            System.debug('From: ' + email.fromAddress);
            System.debug('Subject: ' + email.subject);
            
            // Extract email details
            EmailDetails emailDetails = extractEmailDetails(email, envelope);
            
            // Check if there are any attachments (PDF, DOCX, etc.)
            Boolean hasResume = false;
            if (emailDetails.binaryAttachments != null && !emailDetails.binaryAttachments.isEmpty()) {
                hasResume = true;
                System.debug('Found ' + emailDetails.binaryAttachments.size() + ' binary attachment(s)');
                
                // Process each resume attachment
                for (BinaryAttachmentInfo attachment : emailDetails.binaryAttachments) {
                    String fileName = attachment.fileName.toLowerCase();
                    
                    // Check if it's a resume file (PDF, DOC, DOCX)
                    if (fileName.endsWith('.pdf') || fileName.endsWith('.doc') || 
                        fileName.endsWith('.docx')) {
                        
                        System.debug('Processing resume: ' + attachment.fileName);
                        processResumeAttachment(attachment, emailDetails);
                    }
                }
            }
            
            // If no resume found, create a simple task
            if (!hasResume) {
                System.debug('No resume attachments found - creating simple task');
                createSimpleTask(emailDetails);
            }
            
            result.success = true;
            result.message = 'Email processed successfully';
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Error processing email: ' + e.getMessage();
            System.debug('Error in handleInboundEmail: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
        
        return result;
    }
    
    /**
     * @description Process resume attachment - parse with Claude and create Contact
     */
    private void processResumeAttachment(BinaryAttachmentInfo attachment, EmailDetails emailDetails) {
        try {
            // Convert Blob to Base64
            String base64Content = EncodingUtil.base64Encode(attachment.body);
            String fileName = attachment.fileName;
            String ext = fileName.substringAfterLast('.').toLowerCase();
            
            System.debug('File extension: ' + ext);
            System.debug('Base64 length: ' + base64Content.length());
            
            String pdfBase64 = base64Content;
            String mediaType = 'application/pdf';
            
            // Convert DOCX to PDF if needed
            if (ext == 'docx' || ext == 'doc') {
                System.debug('Converting DOCX to PDF...');
                pdfBase64 = convertDocxToPdf(base64Content, fileName);
                
                if (pdfBase64 == null) {
                    System.debug('DOCX conversion failed - skipping this attachment');
                    return;
                }
                System.debug('DOCX converted successfully');
            }
            
            // Parse resume with Claude
            System.debug('Sending to Claude for parsing...');
            Map<String, Object> parsedData = parseResumeWithClaude(pdfBase64, mediaType);
            Id contactId;
            if (parsedData != null) {
                System.debug('Resume parsed successfully - creating Contact');
                contactId = createContactFromParsedData(parsedData, emailDetails, attachment.fileName);
            }

            // Save the ACTUAL resume file to the Contact
            if (contactId != null) {
                saveActualResumeFile(contactId, attachment.fileName, attachment.body);
            }    
            
        } catch (Exception e) {
            System.debug('Error processing resume: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Create task to notify about the error
            createErrorTask(emailDetails, e.getMessage());
        }
    }
    
    /**
     * @description Convert DOCX to PDF using existing service
     */
    private String convertDocxToPdf(String base64, String fileName) {
        try {
            return calloutUploadS3File1(
                base64, 
                fileName, 
                'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            );
        } catch (Exception e) {
            System.debug('DOCX conversion error: ' + e.getMessage());
            return null;
        }
    }
    
    
    public static string calloutUploadS3File1(string attachmentBody, String fileName ,String contentType){
        
        System.debug('attachmentBody '+attachmentBody);
        System.debug('fileName '+fileName);
        System.debug('contentType '+contentType);
        
        
        String EmailBinaryFileName = fileName;
        if(EmailBinaryFileName.split('\\.').size() > 2){
            String replaceExtraDotWithUnderScore = '';
            for(integer i=0; i<EmailBinaryFileName.split('\\.').size(); i++){
                if(i == 0){
                    System.debug('0th element '+EmailBinaryFileName.split('\\.')[i]);
                    replaceExtraDotWithUnderScore = EmailBinaryFileName.split('\\.')[i];
                    System.debug('replaceExtraDotWithUnderScore first '+replaceExtraDotWithUnderScore);
                }
                else if(i < EmailBinaryFileName.split('\\.').size()-1){
                    System.debug(i+'th element '+EmailBinaryFileName.split('\\.')[i]);
                    replaceExtraDotWithUnderScore += '_'+EmailBinaryFileName.split('\\.')[i];
                    System.debug('replaceExtraDotWithUnderScore middle '+replaceExtraDotWithUnderScore);
                    
                }
                else{
                    System.debug('replaceExtraDotWithUnderScore last '+replaceExtraDotWithUnderScore);
                    replaceExtraDotWithUnderScore += '.'+EmailBinaryFileName.split('\\.')[i];
                    System.debug('replaceExtraDotWithUnderScore last '+replaceExtraDotWithUnderScore);
                }
            }
            System.debug('replaceExtraDotWithUnderScore '+replaceExtraDotWithUnderScore);
            fileName = replaceExtraDotWithUnderScore;
        }
        else{
            System.debug('EmailBinaryFileName '+EmailBinaryFileName);
            fileName = EmailBinaryFileName;
        }
        
        
        String formatted_DateTime = System.now().format('dd-MM-yyyy-HH:mm:ssa');
        System.debug(formatted_DateTime);
        
        String FileRemmoveSpace12  =  fileName.deleteWhitespace();
        System.debug('FileRemmoveSpace' +FileRemmoveSpace12);
        
        String fileExtensionName = FileRemmoveSpace12.split('\\.')[1];
        System.debug('fileNameFormate :'+fileExtensionName);
        
        String FileRemmoveSpecialCharacter = fileName.replaceAll('[^a-zA-Z0-9\\s+]', '');
        System.debug('Name-' + FileRemmoveSpecialCharacter);
        FileRemmoveSpecialCharacter = FileRemmoveSpecialCharacter.replace('+', '');
        String FileRemmoveSpace  =  FileRemmoveSpecialCharacter.deleteWhitespace();
        System.debug('FileRemmoveSpace' +FileRemmoveSpace);
        String fileNameFormate = FileRemmoveSpace.split('\\.')[0];
        
        
        fileName = fileNameFormate+'-'+formatted_DateTime+'.'+fileExtensionName;
        
            String key = System.Label.AWS_Access_Key_Id;
            String secret = System.Label.AWS_Secret_Access_Key;
            String bucketname = System.Label.AWS_S3_Bucket_Name;
            String host = System.Label.AWS_S3_Host;
            
            String formattedDateString = Datetime.now().formatGMT('EEE, dd MMM yyyy HH:mm:ss z');
            
            String method = 'PUT';
            HttpRequest req = new HttpRequest();
            req.setMethod(method);
            req.setEndpoint('https://' + bucketname + '.' + host + '/' + filename);
            req.setHeader('Host', bucketname + '.' + host);
            req.setHeader('Content-Length', String.valueOf(attachmentBody.length()));
            req.setHeader('Content-Encoding', 'UTF-8');
            req.setHeader('Content-type', contentType);
            req.setHeader('Connection', 'keep-alive');
            req.setHeader('Date', formattedDateString);
            req.setHeader('ACL', 'public-read'); //public-read-write

            Blob blobBody = EncodingUtil.base64Decode(attachmentBody);
            
            req.setBodyAsBlob(blobBody);
            
            String stringToSign = 'PUT\n\n' + contentType + '\n' + formattedDateString + '\n' + '/' + bucketname + '/' + filename;
            
            Blob mac = Crypto.generateMac('HMACSHA1', blob.valueof(stringToSign),blob.valueof(secret));
            String signedKey  = EncodingUtil.base64Encode(mac);
            String authHeader = 'AWS' + ' ' + key + ':' + signedKey ;
            req.setHeader('Authorization',authHeader);
            
            
            Http http = new Http();
            System.debug('req: ' + req);
            
            try{
                HTTPResponse res = http.send(req);
                System.debug('res: ' + res);
                System.debug('Contatent Type' + contentType);
                System.debug('*Resp EndPoint:' + req.getEndpoint());
                System.debug('*Resp:' + String.ValueOF(res.getBody()));
                System.debug('RESPONSE STRING: ' + res.toString());
                System.debug('RESPONSE STATUS: ' + res.getStatus());
                System.debug('STATUS_CODE: ' + res.getStatusCode());
               // return res;
               if(res.getStatusCode() == 200 || res.getStatusCode() == 201){
                    System.debug(res.getBody());
                    String fileBase64 = ConvertIntoPdf(fileName);
                    return fileBase64;
               }
                return null;
            }
            catch(Exception e){
                System.debug('Hello Aura : s3 status is faild :'+e.getLineNumber()+e.getMessage());
                
                //SEND FAILURE EMAIL TO admin@resonantcloud.info
                List<String> toaddresses = new List<String>(); 
                for(String EmailDeliveryFailure : System.Label.R_ATS.Email_Service_Failure_Delivery.split(',')){
                    toaddresses.add(EmailDeliveryFailure.trim());
                }
                String Body = '<p> This Error Occured During Uploading Resume Documment to S3 </p>';
                Body += '<p>'+ e.getMessage() +'</p>';
                
                Messaging.SingleEmailMessage mymail = new Messaging.SingleEmailMessage();
                mymail.setToAddresses(toAddresses);
                mymail.setSenderDisplayName('Salesforce Support');
                mymail.setSubject('An Error Occured During Processing a CV');
                mymail.setHtmlBody(Body);
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mymail });
                return null;
            }

    }
    
 	public static string ConvertIntoPdf(String fileName){
        try{
            
            String AccessKey = System.Label.AWS_Access_Key_Id;
            String SecretKey = System.Label.AWS_Secret_Access_Key;
            String BucketName = System.Label.AWS_S3_Bucket_Name;
            String locationname = System.Label.AWS_S3_Host;
            string EndPoint = System.Label.Resume_File_Converter_Endpoint;
            
            System.debug(fileName);
            // String file='KatieCV2docx29112023183850PMdocx-20-05-2024-15:59:13PM.docx';
            String file=fileName;
            
            
            String loc = locationname.substringAfter('s3.');
            String sss = loc.SubStringBefore('.amazonaws.com');
            
            JSONGenerator gen = JSON.createGenerator(true);
            gen.writeStartObject();
            gen.writeStringField('bucketName', BucketName);
            gen.writeStringField('region', sss);
            gen.writeStringField('accessKey', AccessKey);
            gen.writeStringField('secretAccessKey', SecretKey);
            gen.writeEndObject();
            String jsonData = gen.getAsString();
            
            
            String strAWS = EncodingUtil.Base64Encode( Blob.valueOf( jsonData ) );                
            
            
            String newtempate = BucketName + '.' + locationname;
            
            String body1 ='{"path":'+'"https://'+ newtempate +'/'+file+'","aws": '+'"'+strAWS+'"'+'}';
            
            System.debug('EndPoint '+EndPoint);
            System.debug('body1 '+body1);
            
            HttpRequest req = new HttpRequest();
            req.setEndpoint(EndPoint);
            req.setMethod('POST');
            req.setBody(body1);
            req.setHeader('Content-Type','application/json;charset=UTF-8');
            req.setTimeout(120000);
            
            Http http = new Http();
            
            HTTPResponse res = http.send(req);
            System.debug('res 1321 '+res);
            system.debug('----response aws----'+res.getStatusCode());
            system.debug('----response aws----'+res.getBody());
            if(res.getStatusCode() == 200 || res.getStatusCode() == 201){
                
                System.debug('ressssss '+res);
                system.debug('----response aws----'+res.getStatusCode());
                system.debug('----response aws----'+res.getBody());
                Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                // Cast the values in the 'animals' key as a list
                System.debug('results'+results);
                String tempurl = String.valueOf(results.get('filePath'));
                
                String url = tempurl;
                
                String FileNameConvert = tempurl.substringAfter('.amazonaws.com/');
                
                System.debug(loc);
                
                String filename1 = EncodingUtil.urlEncode(FileNameConvert, 'UTF-8');
                
                Datetime now = DateTime.now();
                Datetime expireson = now.AddSeconds(180); // Lifespan of the link
                Long Lexpires = expireson.getTime()/1000;
                
                String stringtosign = 'GET\n\n\n'+Lexpires+'\n/'+BucketName+'/'+filename1;
                
                String signingKey = EncodingUtil.base64Encode(Blob.valueOf(SecretKey));
                Blob mac = Crypto.generateMac('HMacSHA1', blob.valueof(stringtosign),blob.valueof(SecretKey)); 
                String signed= EncodingUtil.base64Encode(mac);     
                String codedsigned = EncodingUtil.urlEncode(signed,'UTF-8');
                url = 'https://'+BucketName+'.'+locationname+'/'+filename1+'?AWSAccessKeyId='+AccessKey+'&Expires='+Lexpires+'&Signature='+codedsigned;
                
                // get Blob value 
                HttpRequest request = new HttpRequest();
                request.setEndpoint(url); 
                request.setMethod('GET');
                
                HttpResponse response1 = new Http().send(request);
                if(response1.getStatusCode() == 200){
                    String base64EncodedString = EncodingUtil.base64Encode(response1.getBodyAsBlob());
                    return base64EncodedString;
                }
                return null;
            }
         
        }
        catch(exception e){
            System.debug('Exceptionnnn '+e.getMessage()+'::'+e.getLineNumber());
            //SEND FAILURE EMAIL TO admin@resonantcloud.info
            List<String> toaddresses = new List<String>(); 
            for(String EmailDeliveryFailure : System.Label.R_ATS.Email_Service_Failure_Delivery.split(',')){
                toaddresses.add(EmailDeliveryFailure.trim());
            }
            String Body = '<p> This Error Occured During Reading Your Resume And Your Current File Extension is not supported !! </p>';
            Body += '<p>'+ e.getMessage() +'</p>';
            
            Messaging.SingleEmailMessage mymail = new Messaging.SingleEmailMessage();
            mymail.setToAddresses(toAddresses);
            mymail.setSenderDisplayName('Salesforce Support');
            mymail.setSubject('An Error Occured During Processing a CV');
            mymail.setHtmlBody(Body);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mymail });
        }
        
        return null;
        
    }
    
    /**
     * @description Parse resume using Claude API
     */
    private Map<String, Object> parseResumeWithClaude(String pdfBase64, String mediaType) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(CLAUDE_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', CLAUDE_API_KEY);
        req.setHeader('anthropic-version', '2023-06-01');
        req.setTimeout(120000);
        
        // Build request with document
        Map<String, Object> documentSource = new Map<String, Object>{
            'type' => 'base64',
            'media_type' => mediaType,
            'data' => pdfBase64
        };
        
        Map<String, Object> documentContent = new Map<String, Object>{
            'type' => 'document',
            'source' => documentSource
        };
        
        Map<String, Object> textContent = new Map<String, Object>{
            'type' => 'text',
            'text' => getExtractionPrompt()
        };
        
        List<Object> contentList = new List<Object>{ documentContent, textContent };
        
        Map<String, Object> userMessage = new Map<String, Object>{
            'role' => 'user',
            'content' => contentList
        };
        
        Map<String, Object> body = new Map<String, Object>{
            'model' => CLAUDE_MODEL,
            'max_tokens' => 4096,
            'messages' => new List<Object>{ userMessage }
        };
        
        req.setBody(JSON.serialize(body));
        
        HttpResponse res = new Http().send(req);
        System.debug('Claude API Status: ' + res.getStatusCode());
        
        if (res.getStatusCode() != 200) {
            System.debug('Claude API Error: ' + res.getBody());
            return null;
        }
        
        // Extract JSON from response
        Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> content = (List<Object>) response.get('content');
        Map<String, Object> textBlock = (Map<String, Object>) content[0];
        String jsonText = (String) textBlock.get('text');
        
        // Clean JSON
        jsonText = jsonText.replace('```json', '').replace('```', '').trim();
        Integer startIdx = jsonText.indexOf('{');
        Integer endIdx = jsonText.lastIndexOf('}');
        if (startIdx >= 0 && endIdx > startIdx) {
            jsonText = jsonText.substring(startIdx, endIdx + 1);
        }
        
        System.debug('Parsed JSON from Claude: ' + jsonText);
        
        return (Map<String, Object>) JSON.deserializeUntyped(jsonText);
    }
    
    /**
     * @description Create Contact from parsed resume data
     */
    private Id createContactFromParsedData(Map<String, Object> data, EmailDetails emailDetails, String fileName) {
        Map<String, Object> personal = (Map<String, Object>) data.get('personalInfo');
        List<Object> workHistory = (List<Object>) data.get('workHistory');
        List<Object> education = (List<Object>) data.get('education');
        List<Object> certifications = (List<Object>) data.get('certifications');
        List<Object> skills = (List<Object>) data.get('skills');
        
        // Create Contact
        Contact con = new Contact();
        
        // Personal Info
        if (personal != null) {
            con.FirstName = getString(personal, 'firstName');
            con.LastName = getString(personal, 'lastName');
            
            // Use email from CV if available, otherwise use sender email
            String cvEmail = getString(personal, 'email');
            con.Email = String.isNotBlank(cvEmail) ? cvEmail : emailDetails.fromAddress;
            
            con.Phone = getString(personal, 'phone');
            con.MobilePhone = getString(personal, 'mobile');
            
            // LinkedIn
            String linkedin = getString(personal, 'linkedIn');
            if (String.isNotBlank(linkedin)) {
                // Assuming you have a custom field for LinkedIn
                // con.LinkedIn__c = linkedin;
            }
            
            // Address
            Map<String, Object> address = (Map<String, Object>) personal.get('address');
            if (address != null) {
                con.MailingStreet = getString(address, 'street');
                con.MailingCity = getString(address, 'city');
                con.MailingState = getString(address, 'state');
                con.MailingPostalCode = getString(address, 'postalCode');
                con.MailingCountry = getString(address, 'country');
            }
        }
        
        // Default last name if not found
        if (String.isBlank(con.LastName)) {
            con.LastName = 'Unknown';
        }
        
        // Work History - Current Job
        if (workHistory != null && !workHistory.isEmpty()) {
            Map<String, Object> currentJob = (Map<String, Object>) workHistory[0];
            con.Title = getString(currentJob, 'title');
            // Assuming custom fields exist:
            con.R_ATS__Current_Designation__c = getString(currentJob, 'title');
            con.R_ATS__Daxtra_Current_Company_Name__c = getString(currentJob, 'company');
        }
        
        // Education
        if (education != null && !education.isEmpty()) {
            Map<String, Object> firstEdu = (Map<String, Object>) education[0];
            // Assuming custom fields exist:
            con.R_ATS__University__c = getString(firstEdu, 'institution');
            con.R_ATS__Qualification__c = getString(firstEdu, 'degree');
        }
        
        // Skills - combine into a text field
        if (skills != null && !skills.isEmpty()) {
            List<String> skillList = new List<String>();
            for (Object skill : skills) {
                skillList.add(String.valueOf(skill));
            }
            // Assuming custom field exists:
            con.R_ATS__Skills__c = String.join(skillList, '; ');
        }
        
        // Summary
        String summary = getString(data, 'summary');
        if (String.isNotBlank(summary)) {
            if (String.isBlank(con.Description)) {
                con.Description = summary;
            } else {
                con.Description = summary + '\n\n' + con.Description;
            }
        }
        
        // Total Years Experience
        Object yearsExp = data.get('totalYearsExperience');
        if (yearsExp != null) {
            // Assuming custom field exists:
            // con.Years_of_Experience__c = Decimal.valueOf(String.valueOf(yearsExp));
        }
        
        // cvText
        String cvText = getString(data, 'extractedText');
        if (cvText != null) {
            // Assuming custom field exists:
             con.R_ATS__Text_CV__c = cvText;
        }
        // Lead Source
        con.LeadSource = 'Email Resume';
        
        System.debug('Creating Contact: ' + con.FirstName + ' ' + con.LastName);
        
        // Check if contact already exists
        List<Contact> existingContacts = [
            SELECT Id, FirstName, LastName, Email
            FROM Contact
            WHERE Email = :con.Email
            LIMIT 1
        ];
        
        if (!existingContacts.isEmpty()) {
            System.debug('Contact already exists with this email. Updating...');
            con.Id = existingContacts[0].Id;
            update con;
            System.debug('Contact updated: ' + con.Id);
        } else {
            insert con;
            System.debug('Contact created: ' + con.Id);
        }
        
        // Create Task linked to Contact
        Task task = new Task();
        task.WhoId = con.Id;
        task.Subject = 'Resume Received: ' + fileName;
        task.Description = 'Resume received via email and parsed automatically.\n\n' +
                          'Sender: ' + emailDetails.fromName + ' <' + emailDetails.fromAddress + '>\n' +
                          'Subject: ' + emailDetails.subject + '\n\n' +
                          'Summary: ' + summary;
        task.Status = 'Completed';
        task.Priority = 'Normal';
        task.ActivityDate = Date.today();
        insert task;
        System.debug('Task created: ' + task.Id);
                
        // Create work history records if you have a custom object
        createWorkHistoryRecords(con.Id, workHistory);
        
        // Create education records if you have a custom object
        createEducationRecords(con.Id, education);
        
        // Create certification records if you have a custom object
        createCertificationRecords(con.Id, certifications);
        
        return con.Id;
    }
    
    /**
     * @description Save resume file to Salesforce Files
     */
    
    private void saveActualResumeFile(Id contactId, String fileName, Blob fileContent) {

        // Create ContentVersion with the ACTUAL file
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;  // Original filename!
        cv.PathOnClient = fileName;
        cv.VersionData = fileContent;  // Original file Blob!
        cv.IsMajorVersion = true;
        insert cv;
        
        ContentVersion insertedCV = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        // Link to Contact
        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = insertedCV.ContentDocumentId;
        cdl.LinkedEntityId = contactId;
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        insert cdl;
    }
    /**
     * @description Create work history records (if you have a custom object)
     */
    private void createWorkHistoryRecords(Id contactId, List<Object> workHistory) {
        if (workHistory == null || workHistory.isEmpty()) {
            return;
        }
        
        // Example if you have Work_History__c custom object:
        
        List<Work_History__c> workRecords = new List<Work_History__c>();
        
        for (Object jobObj : workHistory) {
            Map<String, Object> job = (Map<String, Object>) jobObj;

            Work_History__c wh = new Work_History__c();
            wh.Contact__c = contactId;
            wh.Name = getString(job, 'company');
            wh.Job_Title__c = getString(job, 'title');
            wh.Start_Date__c = parseDate(getString(job, 'startDate'));
            wh.End_Date__c = parseDate(getString(job, 'endDate'));
            wh.Responsibilities__c = getString(job, 'description');
            
            Map<String, Object> locationMap = (Map<String, Object>) job.get('location');
            wh.Work_Location__c = formatLocationAsText(locationMap);
        
            workRecords.add(wh);
        }
        
        if (!workRecords.isEmpty()) {
            insert workRecords;
            System.debug('Created ' + workRecords.size() + ' work history records');
        }
       
        
        System.debug('Work history parsing: ' + workHistory.size() + ' jobs found');
    }
    
    // Add this helper method to your class
    private String formatLocationAsText(Map<String, Object> locationMap) {
        if (locationMap == null) return null;
        
        String city = (String) locationMap.get('city');
        String state = (String) locationMap.get('state');
        String country = (String) locationMap.get('country');
        
        List<String> parts = new List<String>();
        if (String.isNotBlank(city)) parts.add(city);
        if (String.isNotBlank(state)) parts.add(state);
        if (String.isNotBlank(country)) parts.add(country);
        
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }
    
    private void createCertificationRecords(Id contactId, List<Object> certifications){
        if (certifications == null || certifications.isEmpty()) {
            return;
        }
    
        List<Certification__c> certRecords = new List<Certification__c>();
        
        for (Object cert : certifications) {
            
            Certification__c cer = new Certification__c();
            cer.Contact__c = contactId;
            cer.Name = String.valueOf(cert);
            certRecords.add(cer);
        }

        
        if (!certRecords.isEmpty()) {
            insert certRecords;
            System.debug('Created ' + certRecords.size() + ' certification records');
        }
      
        
        System.debug('certifications parsing: ' + certRecords.size() + ' certifications records found');
    }
    /**
     * @description Create education records (if you have a custom object)
     */
    private void createEducationRecords(Id contactId, List<Object> education) {
        if (education == null || education.isEmpty()) {
            return;
        }
        
        // Example if you have Education__c custom object:
    
        List<Education__c> eduRecords = new List<Education__c>();
        
        for (Object eduObj : education) {
            Map<String, Object> edu = (Map<String, Object>) eduObj;
            
            Education__c ed = new Education__c();
            ed.Contact__c = contactId;
            ed.Institution__c = getString(edu, 'institution');
            ed.Name = getString(edu, 'degree');
            ed.Field_of_Study__c = getString(edu, 'major');
            ed.Graduation_Year__c = getString(edu, 'graduationYear');
            
            eduRecords.add(ed);
        }
        
        if (!eduRecords.isEmpty()) {
            insert eduRecords;
            System.debug('Created ' + eduRecords.size() + ' education records');
        }
      
        
        System.debug('Education parsing: ' + education.size() + ' education records found');
    }
    
    /**
     * @description Create simple task when no resume found
     */
    private void createSimpleTask(EmailDetails details) {
        Task emailTask = new Task();
        emailTask.Subject = 'Email: ' + (details.subject != null ? details.subject : 'No Subject');
        emailTask.Description = buildEmailDescription(details);
        emailTask.ActivityDate = Date.today();
        emailTask.Status = 'Not Started';
        emailTask.Priority = 'Normal';
        
        // Try to associate with Contact/Lead
        List<Contact> contacts = [
            SELECT Id FROM Contact WHERE Email = :details.fromAddress LIMIT 1
        ];
        
        if (!contacts.isEmpty()) {
            emailTask.WhoId = contacts[0].Id;
        } else {
            List<Lead> leads = [
                SELECT Id FROM Lead WHERE Email = :details.fromAddress LIMIT 1
            ];
            if (!leads.isEmpty()) {
                emailTask.WhoId = leads[0].Id;
            }
        }
        
        insert emailTask;
        System.debug('Simple task created: ' + emailTask.Id);
    }
    
    /**
     * @description Create error task when resume parsing fails
     */
    private void createErrorTask(EmailDetails details, String errorMessage) {
        Task errorTask = new Task();
        errorTask.Subject = 'Resume Parsing Error: ' + details.subject;
        errorTask.Description = 'An error occurred while parsing the resume:\n\n' +
                               'Error: ' + errorMessage + '\n\n' +
                               'From: ' + details.fromName + ' <' + details.fromAddress + '>\n' +
                               'Subject: ' + details.subject;
        errorTask.ActivityDate = Date.today();
        errorTask.Status = 'Not Started';
        errorTask.Priority = 'High';
        insert errorTask;
    }
    
    /**
     * @description Get extraction prompt for Claude
     */
    private String getExtractionPrompt() {
        return 'You are an expert CV/Resume parser. Extract ALL information from this CV document.\n\n' +
            'IMPORTANT:\n' +
            '- Extract EVERY job position from work/professional experience section\n' +
            '- Extract EVERY education entry (degrees, universities)\n' +
            '- Extract job locations (city, state, country)\n' +
            '- Convert job descriptions into numbered bullet points\n' +
            '- Do NOT skip any entries\n\n' +
            'Return ONLY a valid JSON object with this EXACT structure:\n' +
            '{\n' +
            '  "personalInfo": {\n' +
            '    "firstName": "string",\n' +
            '    "lastName": "string",\n' +
            '    "email": "string",\n' +
            '    "phone": "string",\n' +
            '    "mobile": "string",\n' +
            '    "linkedIn": "string",\n' +
            '    "address": { "street": "string", "city": "string", "state": "string", "postalCode": "string", "country": "string" }\n' +
            '  },\n' +
            '  "workHistory": [\n' +
            '    {\n' +
            '      "company": "company name",\n' +
            '      "title": "job title",\n' +
            '      "location": { "city": "city name", "state": "state/province", "country": "country name" },\n' +
            '      "startDate": "YYYY-MM",\n' +
            '      "endDate": "YYYY-MM or Present",\n' +
            '      "description": "1. First responsibility\\n2. Second responsibility\\n3. Third responsibility"\n' +
            '    }\n' +
            '  ],\n' +
            '  "education": [\n' +
            '    {\n' +
            '      "institution": "university name",\n' +
            '      "degree": "degree name",\n' +
            '      "major": "field of study",\n' +
            '      "graduationYear": "YYYY"\n' +
            '    }\n' +
            '  ],\n' +
            '  "skills": ["skill1", "skill2"],\n' +
            '  "certifications": ["cert1", "cert2"],\n' +
            '  "summary": "2-3 sentence professional summary",\n' +
            '  "totalYearsExperience": 0,\n' +
            '  "extractedText": "FULL TEXT OF THE CV WITH PROPER FORMATTING - preserve line breaks using \\n, preserve section headers, preserve bullet points, maintain the original structure and readability of the document"\n' +
            '}\n\n' +
            'RULES:\n' +
            '1. Extract ALL jobs - this CV should have multiple positions\n' +
            '2. Extract ALL education - look for degrees, universities, graduation years\n' +
            '3. For each job, extract location (city, state, country) if mentioned\n' +
            '4. Convert job descriptions into numbered bullet points (1. 2. 3. etc.)\n' +
            '5. Use \\n to separate lines, description and sections in all text fields\n' +
            '6. Convert month names to numbers (June=06, August=08)\n' +
            '7. Use "" for missing strings, [] for missing arrays, {"city":"","state":"","country":""} for missing location\n' +
            '8. For extractedText: Include the COMPLETE readable text from the CV\n' +
            '   - Preserve all section headers (e.g., "EXPERIENCE", "EDUCATION", "SKILLS")\n' +
            '   - Use \\n for line breaks\n' +
            '   - Use \\n\\n for section breaks\n' +
            '   - Preserve bullet points as "• " or "- "\n' +
            '   - Keep the original formatting structure\n' +
            '9. Return ONLY JSON - no markdown, no explanation';
    }
    
    // ==================== HELPER METHODS ====================
    
    private String getString(Map<String, Object> maps, String key) {
        Object value = maps.get(key);
        return value != null ? String.valueOf(value) : '';
    }
    
    private Date parseDate(String dateStr) {
        if (String.isBlank(dateStr) || dateStr == 'Present') {
            return null;
        }
        try {
            List<String> parts = dateStr.split('-');
            if (parts.size() == 2) {
                return Date.newInstance(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), 1);
            }
        } catch (Exception e) {
            System.debug('Error parsing date: ' + dateStr);
        }
        return null;
    }
    
    private EmailDetails extractEmailDetails(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        EmailDetails details = new EmailDetails();
        
        details.subject = email.subject;
        details.fromAddress = email.fromAddress;
        details.fromName = email.fromName;
        details.replyTo = email.replyTo;
        details.messageId = email.messageId;
        details.inReplyTo = email.inReplyTo;
        details.references = email.references;
        details.plainTextBody = email.plainTextBody;
        details.htmlBody = email.htmlBody;
        details.toAddress = envelope.toAddress;
        details.fromEnvelopeAddress = envelope.fromAddress;
        details.toAddresses = email.toAddresses;
        details.ccAddresses = email.ccAddresses;
        details.headers = email.headers;
        
        if (email.headers != null && !email.headers.isEmpty()) {
            for (Messaging.InboundEmail.Header header : email.headers) {
                details.headerMap.put(header.name, header.value);
            }
        }
        
        if (email.binaryAttachments != null && !email.binaryAttachments.isEmpty()) {
            details.binaryAttachments = new List<BinaryAttachmentInfo>();
            for (Messaging.InboundEmail.BinaryAttachment binAttachment : email.binaryAttachments) {
                BinaryAttachmentInfo attInfo = new BinaryAttachmentInfo();
                attInfo.fileName = binAttachment.fileName;
                attInfo.body = binAttachment.body;
                attInfo.mimeTypeSubType = binAttachment.mimeTypeSubType;
                attInfo.fileSize = binAttachment.body != null ? binAttachment.body.size() : 0;
                details.binaryAttachments.add(attInfo);
            }
        }
        
        return details;
    }
    
    private String buildEmailDescription(EmailDetails details) {
        String description = '';
        description += 'From: ' + details.fromName + ' <' + details.fromAddress + '>\n';
        description += 'To: ' + details.toAddress + '\n';
        if (details.ccAddresses != null && !details.ccAddresses.isEmpty()) {
            description += 'CC: ' + String.join(details.ccAddresses, ', ') + '\n';
        }
        if (details.replyTo != null) {
            description += 'Reply-To: ' + details.replyTo + '\n';
        }
        description += 'Subject: ' + details.subject + '\n\n';
        description += '--- Email Body ---\n';
        description += details.plainTextBody != null ? details.plainTextBody : 'No plain text body';
        return description;
    }
    
    // ==================== WRAPPER CLASSES ====================
    
    public class EmailDetails {
        public String subject;
        public String fromAddress;
        public String fromName;
        public String replyTo;
        public String messageId;
        public String inReplyTo;
        public List<String> references;
        public String plainTextBody;
        public String htmlBody;
        public String toAddress;
        public String fromEnvelopeAddress;
        public List<String> toAddresses;
        public List<String> ccAddresses;
        public List<Messaging.InboundEmail.Header> headers;
        public Map<String, String> headerMap;
        public List<BinaryAttachmentInfo> binaryAttachments;
        
        public EmailDetails() {
            this.headerMap = new Map<String, String>();
            this.binaryAttachments = new List<BinaryAttachmentInfo>();
        }
    }
    
    public class BinaryAttachmentInfo {
        public String fileName;
        public Blob body;
        public String mimeTypeSubType;
        public Integer fileSize;
    }
}
