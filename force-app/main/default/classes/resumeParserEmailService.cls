/**
 * @description Email Service that receives resumes and automatically parses them using Claude AI
 * @author Your Name
 * @date 2026-01-08
 */
global class resumeParserEmailService implements Messaging.InboundEmailHandler {
    
    private static final String CLAUDE_MODEL = 'claude-sonnet-5';
    private static final String CLAUDE_ENDPOINT = 'https://api.anthropic.com/v1/messages';
    private static final String DEFAULT_AWS_BUCKET_NAME = 'resonanttest2021';
    private static final String DEFAULT_AWS_HOST = 's3.us-west-2.amazonaws.com';
    private String lastParseError;

    public static UploadResult parseUploadedResumeForContact(Id contactId, String fileName, String base64Content, String contentType) {
        UploadResult result = new UploadResult();
        if (contactId == null) {
            result.success = false;
            result.message = 'Missing contactId';
            return result;
        }
        if (String.isBlank(fileName) || String.isBlank(base64Content)) {
            result.success = false;
            result.message = 'Missing file';
            return result;
        }

        String lowerName = fileName.toLowerCase();
        if (!(lowerName.endsWith('.pdf') || lowerName.endsWith('.doc') || lowerName.endsWith('.docx'))) {
            result.success = false;
            result.message = 'Only PDF, DOC, and DOCX files are supported';
            return result;
        }

        resumeParserEmailService parser = new resumeParserEmailService();
        Blob fileBody = EncodingUtil.base64Decode(base64Content);
        String ext = lowerName.substringAfterLast('.');
        String pdfBase64 = base64Content;
        String mediaType = 'application/pdf';

        if (ext == 'doc' || ext == 'docx') {
            pdfBase64 = parser.convertDocxToPdf(base64Content, fileName);
            if (String.isBlank(pdfBase64)) {
                result.success = false;
                result.message = 'Unable to convert Word document to PDF for parsing';
                return result;
            }
        }

        Map<String, Object> parsedData = parser.parseResumeWithClaude(pdfBase64, mediaType, contactId);
        if (parsedData == null) {
            result.success = false;
            result.message = String.isBlank(parser.lastParseError)
                ? 'Unable to parse CV'
                : 'Unable to parse CV: ' + parser.lastParseError;
            return result;
        }

        parser.updateExistingContactFromParsedData(contactId, parsedData, fileName);
        parser.saveActualResumeFile(contactId, fileName, fileBody);
        parser.publishCVProcessingComplete(contactId, fileName);

        result.success = true;
        result.message = 'CV parsed successfully';
        result.contactId = contactId;
        result.data = parsedData;
        return result;
    }
    
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
            Map<String, Object> parsedData = parseResumeWithClaude(pdfBase64, mediaType, null);
            Id contactId;
            if (parsedData != null) {
                System.debug('Resume parsed successfully - creating Contact');
                contactId = createContactFromParsedData(parsedData, emailDetails, attachment.fileName);
            }

            // Save the ACTUAL resume file to the Contact
            if (contactId != null) {
                saveActualResumeFile(contactId, attachment.fileName, attachment.body);
                publishCVProcessingComplete(contactId, attachment.fileName);
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
        
            AwsSettings awsSettings = getAwsSettings();
            String key = awsSettings.accessKey;
            String secret = awsSettings.secretKey;
            String bucketname = awsSettings.bucketName;
            String host = awsSettings.host;
            
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
            
            AwsSettings awsSettings = getAwsSettings();
            String AccessKey = awsSettings.accessKey;
            String SecretKey = awsSettings.secretKey;
            String BucketName = awsSettings.bucketName;
            String locationname = awsSettings.host;
            string EndPoint = 'https://resonant-file-converter.herokuapp.com/api/convert/docx-pdf';  //end point URL
            
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
    private Map<String, Object> parseResumeWithClaude(String pdfBase64, String mediaType, Id contactId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(CLAUDE_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('x-api-key', getClaudeAPIKey());
        req.setHeader('anthropic-version', '2023-06-01');
        req.setHeader('anthropic-beta', 'pdfs-2024-09-25');
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
            'max_tokens' => 8192,
            'messages' => new List<Object>{ userMessage }
        };
        
        req.setBody(JSON.serialize(body));
        
        Long started = DateTime.now().getTime();
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception calloutException) {
            logResumeClaudeFailure(contactId, mediaType, pdfBase64 == null ? 0 : pdfBase64.length(), calloutException.getMessage(), started);
            throw calloutException;
        }
        logResumeClaudeCall(contactId, mediaType, pdfBase64 == null ? 0 : pdfBase64.length(), res, started);
        System.debug('Claude API Status: ' + res.getStatusCode());
        
        if (res.getStatusCode() != 200) {
            System.debug('Claude API Error: ' + res.getBody());
            lastParseError = 'Claude API ' + res.getStatusCode() + ': ' + limitErrorMessage(res.getBody());
            return null;
        }
        
        // Extract JSON from response. Claude can return a 200 with no text block,
        // so guard every response shape before cleaning/parsing.
        String jsonText;
        try {
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Object> content = (List<Object>) response.get('content');
            if (content == null || content.isEmpty()) {
                lastParseError = 'Claude response missing content: ' + limitErrorMessage(res.getBody());
                System.debug(lastParseError);
                return null;
            }

            for (Object blockObject : content) {
                if (blockObject == null) continue;
                try {
                    Map<String, Object> block = (Map<String, Object>) blockObject;
                    String blockText = (String) block.get('text');
                    if (String.isNotBlank(blockText)) {
                        jsonText = blockText;
                        break;
                    }
                } catch (Exception ignoredBlock) {
                    System.debug('Skipping non-text Claude content block: ' + ignoredBlock.getMessage());
                }
            }
        } catch (Exception responseParseException) {
            lastParseError = 'Claude response parse failed: ' + responseParseException.getMessage();
            System.debug(lastParseError);
            return null;
        }

        if (String.isBlank(jsonText)) {
            lastParseError = 'Claude response missing text block: ' + limitErrorMessage(res.getBody());
            System.debug(lastParseError);
            return null;
        }
        
        // Clean JSON
        jsonText = jsonText.replace('```json', '').replace('```', '').trim();
        Integer startIdx = jsonText.indexOf('{');
        Integer endIdx = jsonText.lastIndexOf('}');
        if (startIdx >= 0 && endIdx > startIdx) {
            jsonText = jsonText.substring(startIdx, endIdx + 1);
        } else {
            lastParseError = 'Claude response did not contain JSON: ' + limitErrorMessage(jsonText);
            System.debug(lastParseError);
            return null;
        }
        
        System.debug('Parsed JSON from Claude: ' + jsonText);
        
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(jsonText);
        } catch (Exception parseException) {
            lastParseError = 'Claude returned invalid JSON: ' + parseException.getMessage();
            System.debug('Claude JSON parse error: ' + parseException.getMessage());
            return null;
        }
    }

    private static void logResumeClaudeCall(Id contactId, String mediaType, Integer payloadChars, HttpResponse res, Long started) {
        try {
            AIAPILogService.LogEntry entry = new AIAPILogService.LogEntry();
            entry.operation = 'CV Parse';
            entry.requestType = 'CV_Parse';
            entry.contactId = contactId;
            entry.requestPayload = 'model=' + CLAUDE_MODEL +
                '\nmediaType=' + mediaType +
                '\npayloadChars=' + String.valueOf(payloadChars) +
                '\nsource=resumeParserEmailService';
            entry.responsePayload = res == null ? null : res.getBody();
            entry.status = res != null && res.getStatusCode() >= 200 && res.getStatusCode() < 300 ? 'Success' : 'Failed';
            entry.errorMessage = entry.status == 'Failed' && res != null
                ? 'Claude API HTTP ' + res.getStatusCode()
                : null;
            entry.model = CLAUDE_MODEL;
            entry.durationMs = Integer.valueOf(String.valueOf(DateTime.now().getTime() - started));
            entry.httpStatusCode = res == null ? null : res.getStatusCode();
            if (res != null && String.isNotBlank(res.getBody()) && res.getStatusCode() == 200) {
                Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                Map<String, Object> usage = (Map<String, Object>) responseBody.get('usage');
                if (usage != null) {
                    entry.inputTokens = integerValue(usage.get('input_tokens'));
                    entry.outputTokens = integerValue(usage.get('output_tokens'));
                    entry.totalTokens = (entry.inputTokens == null ? 0 : entry.inputTokens) + (entry.outputTokens == null ? 0 : entry.outputTokens);
                }
            }
            AIAPILogService.logClaudeCall(entry);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Resume Claude API log skipped: ' + e.getMessage());
        }
    }

    private static void logResumeClaudeFailure(Id contactId, String mediaType, Integer payloadChars, String errorMessage, Long started) {
        try {
            AIAPILogService.LogEntry entry = new AIAPILogService.LogEntry();
            entry.operation = 'CV Parse';
            entry.requestType = 'CV_Parse';
            entry.contactId = contactId;
            entry.requestPayload = 'model=' + CLAUDE_MODEL +
                '\nmediaType=' + mediaType +
                '\npayloadChars=' + String.valueOf(payloadChars) +
                '\nsource=resumeParserEmailService';
            entry.status = 'Failed';
            entry.errorMessage = errorMessage;
            entry.model = CLAUDE_MODEL;
            entry.durationMs = Integer.valueOf(String.valueOf(DateTime.now().getTime() - started));
            AIAPILogService.logClaudeCall(entry);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Resume Claude failure log skipped: ' + e.getMessage());
        }
    }

    private static Integer integerValue(Object value) {
        if (value == null) return null;
        try {
            return Integer.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
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
            String socialLinks = formatSocialProfileLinks(personal);
            if (String.isNotBlank(socialLinks)) {
                con.Social_Profile_Links__c = socialLinks;
            }
            
            // Address
            Map<String, Object> address = (Map<String, Object>) personal.get('address');
            if (address != null) {
                applyMailingAddress(con, address);
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
        
        // Skills - replace with latest parsed CV skills
        if (skills != null && !skills.isEmpty()) {
            List<String> skillList = new List<String>();
            for (Object skill : skills) {
                skillList.add(String.valueOf(skill));
            }
            con.R_ATS__Skills__c = mergeSkillText(null, skillList);
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
        
        Decimal totalYearsExperience = parseDecimal(data.get('totalYearsExperience'));
        if (totalYearsExperience != null) {
            con.Years_Experience__c = totalYearsExperience;
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
            SELECT Id, FirstName, LastName, Email, R_ATS__Skills__c
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
        syncCareerIntentSkills(con.Id, con.R_ATS__Skills__c);
        
        // Create Task linked to Contact
        createResumeTaskIfMissing(
            con.Id,
            'Resume Received: ' + fileName,
            'Resume received via email and parsed automatically.\n\n' +
            'Sender: ' + emailDetails.fromName + ' <' + emailDetails.fromAddress + '>\n' +
            'Subject: ' + emailDetails.subject + '\n\n' +
            'Summary: ' + summary
        );
                
        // Create work history records if you have a custom object
        createWorkHistoryRecords(con.Id, workHistory);
        updateContactExperienceFromWorkHistory(con.Id);
        
        // Create education records if you have a custom object
        createEducationRecords(con.Id, education);
        
        // Create certification records if you have a custom object
        createCertificationRecords(con.Id, certifications);
        
        return con.Id;
    }

    private void updateExistingContactFromParsedData(Id contactId, Map<String, Object> data, String fileName) {
        List<Contact> contacts = [
            SELECT Id, Description, R_ATS__Skills__c, Social_Profile_Links__c
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            throw new ResumeParserConfigurationException('Contact not found');
        }

        List<Object> workHistory = (List<Object>) data.get('workHistory');
        List<Object> education = (List<Object>) data.get('education');
        List<Object> certifications = (List<Object>) data.get('certifications');
        List<Object> skills = (List<Object>) data.get('skills');
        Map<String, Object> personal = (Map<String, Object>) data.get('personalInfo');

        Contact existingContact = contacts[0];
        Contact con = new Contact(Id = contactId);

        if (personal != null) {
            String socialLinks = formatSocialProfileLinks(personal);
            if (String.isNotBlank(socialLinks)) {
                con.Social_Profile_Links__c = socialLinks;
            }

            Map<String, Object> address = (Map<String, Object>) personal.get('address');
            if (address != null) {
                applyMailingAddress(con, address);
            }
        }

        if (workHistory != null && !workHistory.isEmpty()) {
            Map<String, Object> currentJob = (Map<String, Object>) workHistory[0];
            con.Title = getString(currentJob, 'title');
            con.R_ATS__Current_Designation__c = getString(currentJob, 'title');
            con.R_ATS__Daxtra_Current_Company_Name__c = getString(currentJob, 'company');
        }

        if (education != null && !education.isEmpty()) {
            Map<String, Object> firstEdu = (Map<String, Object>) education[0];
            con.R_ATS__University__c = getString(firstEdu, 'institution');
            con.R_ATS__Qualification__c = getString(firstEdu, 'degree');
        }

        if (skills != null && !skills.isEmpty()) {
            List<String> skillList = new List<String>();
            for (Object skill : skills) {
                skillList.add(String.valueOf(skill));
            }
            con.R_ATS__Skills__c = mergeSkillText(null, skillList);
        }

        String summary = getString(data, 'summary');
        if (String.isNotBlank(summary)) {
            con.Description = String.isBlank(existingContact.Description)
                ? summary
                : summary + '\n\n' + existingContact.Description;
        }

        String cvText = getString(data, 'extractedText');
        if (cvText != null) {
            con.R_ATS__Text_CV__c = cvText;
        }

        Decimal totalYearsExperience = parseDecimal(data.get('totalYearsExperience'));
        if (totalYearsExperience != null) {
            con.Years_Experience__c = totalYearsExperience;
        }

        con.LeadSource = 'Candidate Portal CV Upload';

        update con;
        syncCareerIntentSkills(contactId, con.R_ATS__Skills__c);

        createResumeTaskIfMissing(
            contactId,
            'CV Uploaded: ' + fileName,
            'CV uploaded from candidate portal and parsed automatically.\n\nSummary: ' + summary
        );

        createWorkHistoryRecords(contactId, workHistory);
        updateContactExperienceFromWorkHistory(contactId);
        createEducationRecords(contactId, education);
        createCertificationRecords(contactId, certifications);
    }
    
    /**
     * @description Save resume file to Salesforce Files
     */
    
    private void saveActualResumeFile(Id contactId, String fileName, Blob fileContent) {
        if (hasExistingResumeFile(contactId, fileName)) {
            System.debug('Resume file already linked to contact, skipping duplicate file: ' + fileName);
            return;
        }

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

    private Boolean hasExistingResumeFile(Id contactId, String fileName) {
        if (contactId == null || String.isBlank(fileName)) return false;
        List<ContentDocumentLink> links = [
            SELECT Id
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :contactId
            AND ContentDocument.Title = :fileName
            LIMIT 1
        ];
        return !links.isEmpty();
    }

    private void createResumeTaskIfMissing(Id contactId, String subject, String description) {
        if (contactId == null || String.isBlank(subject)) return;
        List<Task> existingTasks = [
            SELECT Id
            FROM Task
            WHERE WhoId = :contactId
            AND Subject = :subject
            LIMIT 1
        ];
        if (!existingTasks.isEmpty()) {
            System.debug('Resume task already exists, skipping duplicate task: ' + subject);
            return;
        }

        Task task = new Task();
        task.WhoId = contactId;
        task.Subject = subject;
        task.Description = description;
        task.Status = 'Completed';
        task.Priority = 'Normal';
        task.ActivityDate = Date.today();
        insert task;
        System.debug('Resume task created: ' + task.Id);
    }

    private void publishCVProcessingComplete(Id contactId, String fileName) {
        EventBus.publish(new CV_Processing_Complete__e(
            Contact_Id__c = String.valueOf(contactId),
            Source__c = 'Email Resume Parser',
            File_Name__c = fileName
        ));
    }
    /**
     * @description Create work history records (if you have a custom object)
     */
    private void createWorkHistoryRecords(Id contactId, List<Object> workHistory) {
        if (workHistory == null || workHistory.isEmpty()) {
            return;
        }
        
        // Example if you have Work_History__c custom object:
        
        Set<String> existingKeys = new Set<String>();
        for (Work_History__c existing : [
            SELECT Name, Job_Title__c, Start_Date__c, End_Date__c
            FROM Work_History__c
            WHERE Contact__c = :contactId
        ]) {
            existingKeys.add(workHistoryKey(existing.Name, existing.Job_Title__c, existing.Start_Date__c, existing.End_Date__c));
        }

        List<Work_History__c> workRecords = new List<Work_History__c>();
        
        for (Object jobObj : workHistory) {
            Map<String, Object> job = (Map<String, Object>) jobObj;
            String company = getString(job, 'company');
            String title = getString(job, 'title');
            Date startDate = parseDate(getString(job, 'startDate'));
            Date endDate = parseDate(getString(job, 'endDate'));
            String key = workHistoryKey(company, title, startDate, endDate);
            if (existingKeys.contains(key)) continue;

            Work_History__c wh = new Work_History__c();
            wh.Contact__c = contactId;
            wh.Name = company;
            wh.Job_Title__c = title;
            wh.Start_Date__c = startDate;
            wh.End_Date__c = endDate;
            wh.Responsibilities__c = getString(job, 'description');
            
            Map<String, Object> locationMap = (Map<String, Object>) job.get('location');
            wh.Work_Location__c = formatLocationAsText(locationMap);
        
            workRecords.add(wh);
            existingKeys.add(key);
        }
        
        if (!workRecords.isEmpty()) {
            insert workRecords;
            System.debug('Created ' + workRecords.size() + ' work history records');
        }
       
        
        System.debug('Work history parsing: ' + workHistory.size() + ' jobs found');
    }

    private String workHistoryKey(String company, String title, Date startDate, Date endDate) {
        return normalizeKey(company) + '|' +
            normalizeKey(title) + '|' +
            String.valueOf(startDate) + '|' +
            String.valueOf(endDate);
    }

    private void updateContactExperienceFromWorkHistory(Id contactId) {
        if (contactId == null) return;

        Integer totalMonths = 0;
        for (Work_History__c history : [
            SELECT Start_Date__c, End_Date__c
            FROM Work_History__c
            WHERE Contact__c = :contactId
        ]) {
            totalMonths += countWorkHistoryMonths(history.Start_Date__c, history.End_Date__c);
        }

        if (totalMonths <= 0) return;

        update new Contact(
            Id = contactId,
            Years_Experience__c = monthsToYearMonthDecimal(totalMonths)
        );
    }

    private Integer countWorkHistoryMonths(Date startDate, Date endDate) {
        if (startDate == null) return 0;
        Date effectiveEndDate = endDate == null ? Date.today() : endDate;
        if (effectiveEndDate < startDate) return 0;

        return Math.max(0, startDate.monthsBetween(effectiveEndDate));
    }

    private Decimal monthsToYearMonthDecimal(Integer totalMonths) {
        if (totalMonths == null || totalMonths <= 0) return 0;
        Integer years = totalMonths / 12;
        Integer months = Math.mod(totalMonths, 12);
        return Decimal.valueOf(String.valueOf(years) + '.' + String.valueOf(months));
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
    
        Set<String> existingKeys = new Set<String>();
        for (Certification__c existing : [
            SELECT Name
            FROM Certification__c
            WHERE Contact__c = :contactId
        ]) {
            existingKeys.add(normalizeKey(existing.Name));
        }

        List<Certification__c> certRecords = new List<Certification__c>();
        
        for (Object cert : certifications) {
            String certName = String.valueOf(cert);
            String key = normalizeKey(certName);
            if (String.isBlank(key) || existingKeys.contains(key)) continue;
            
            Certification__c cer = new Certification__c();
            cer.Contact__c = contactId;
            cer.Name = certName;
            certRecords.add(cer);
            existingKeys.add(key);
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
    
        Set<String> existingKeys = new Set<String>();
        for (Education__c existing : [
            SELECT Institution__c, Name, Field_of_Study__c, Graduation_Year__c
            FROM Education__c
            WHERE Contact__c = :contactId
        ]) {
            existingKeys.add(educationKey(existing.Institution__c, existing.Name, existing.Field_of_Study__c, existing.Graduation_Year__c));
        }

        List<Education__c> eduRecords = new List<Education__c>();
        
        for (Object eduObj : education) {
            Map<String, Object> edu = (Map<String, Object>) eduObj;
            String institution = getString(edu, 'institution');
            String degree = getString(edu, 'degree');
            String major = getString(edu, 'major');
            String graduationYear = getString(edu, 'graduationYear');
            EducationParts parts = normalizeEducationParts(degree, major);
            degree = parts.degree;
            major = parts.fieldOfStudy;
            String key = educationKey(institution, degree, major, graduationYear);
            if (existingKeys.contains(key)) continue;
            
            Education__c ed = new Education__c();
            ed.Contact__c = contactId;
            ed.Institution__c = institution;
            ed.Name = degree;
            ed.Field_of_Study__c = major;
            ed.Graduation_Year__c = graduationYear;
            
            eduRecords.add(ed);
            existingKeys.add(key);
        }
        
        if (!eduRecords.isEmpty()) {
            insert eduRecords;
            System.debug('Created ' + eduRecords.size() + ' education records');
        }
      
        
        System.debug('Education parsing: ' + education.size() + ' education records found');
    }

    private String educationKey(String institution, String degree, String major, String graduationYear) {
        return normalizeKey(institution) + '|' +
            normalizeKey(degree) + '|' +
            normalizeKey(major) + '|' +
            normalizeKey(graduationYear);
    }

    private class EducationParts {
        String degree;
        String fieldOfStudy;
        EducationParts(String degree, String fieldOfStudy) {
            this.degree = degree;
            this.fieldOfStudy = fieldOfStudy;
        }
    }

    private EducationParts normalizeEducationParts(String rawDegree, String rawField) {
        String degree = cleanEducationText(rawDegree);
        String field = cleanEducationText(rawField);

        if (String.isNotBlank(field)) {
            degree = removeFieldFromDegree(degree, field);
            return new EducationParts(cleanDegreeName(degree), field);
        }

        EducationParts split = splitDegreeAndField(degree);
        return new EducationParts(cleanDegreeName(split.degree), split.fieldOfStudy);
    }

    private String cleanEducationText(String value) {
        if (String.isBlank(value)) return '';
        return value.trim().replaceAll('\\s+', ' ');
    }

    private String removeFieldFromDegree(String degree, String field) {
        if (String.isBlank(degree) || String.isBlank(field)) return degree;
        String escapedField = Pattern.quote(field);
        String cleaned = degree
            .replaceAll('(?i)\\s+(majoring in|majored in|major in|specialization in|specialized in|specializing in|concentration in|concentrated in|focus in|focused in|emphasis in|option in|stream in|track in|pathway in|discipline of|field of|program in|course in|degree in|honours in|honors in|minor in|double major in|in|for|with)\\s+' + escapedField + '$', '')
            .replaceAll('(?i)\\s*[-–—:,/]\\s*' + escapedField + '$', '')
            .replaceAll('(?i)\\s*\\(\\s*' + escapedField + '\\s*\\)\\s*$', '')
            .trim();
        return String.isBlank(cleaned) ? degree : cleaned;
    }

    private EducationParts splitDegreeAndField(String degree) {
        if (String.isBlank(degree)) return new EducationParts('', '');

        List<String> separatorPatterns = new List<String>{
            '\\s+majoring in\\s+', '\\s+majored in\\s+', '\\s+major in\\s+',
            '\\s+specialization in\\s+', '\\s+specialized in\\s+', '\\s+specializing in\\s+',
            '\\s+concentration in\\s+', '\\s+concentrated in\\s+', '\\s+focus in\\s+', '\\s+focused in\\s+',
            '\\s+emphasis in\\s+', '\\s+option in\\s+', '\\s+stream in\\s+', '\\s+track in\\s+',
            '\\s+pathway in\\s+', '\\s+discipline of\\s+', '\\s+field of\\s+', '\\s+program in\\s+',
            '\\s+course in\\s+', '\\s+degree in\\s+', '\\s+honours in\\s+', '\\s+honors in\\s+',
            '\\s+minor in\\s+', '\\s+double major in\\s+', '\\s+in\\s+', '\\s+for\\s+', '\\s+with\\s+',
            '\\s*[-–—:]\\s+', '\\s*,\\s+'
        };

        for (String pattern : separatorPatterns) {
            List<String> pieces = degree.split('(?i)' + pattern, 2);
            if (pieces.size() == 2 && String.isNotBlank(pieces[0]) && String.isNotBlank(pieces[1])) {
                return new EducationParts(cleanEducationText(pieces[0]), cleanEducationText(pieces[1]));
            }
        }

        Matcher parenMatcher = Pattern.compile('^(.+?)\\s*\\(([^)]+)\\)\\s*$').matcher(degree);
        if (parenMatcher.matches()) {
            return new EducationParts(cleanEducationText(parenMatcher.group(1)), cleanEducationText(parenMatcher.group(2)));
        }

        List<String> degreePrefixes = new List<String>{
            'B.A.', 'B.A', 'BA', 'B.S.', 'B.S', 'BS', 'B.Sc.', 'B.Sc', 'BSc',
            'B.Tech', 'BTech', 'B.E.', 'B.E', 'BE', 'M.A.', 'M.A', 'MA',
            'M.S.', 'M.S', 'MS', 'M.Sc.', 'M.Sc', 'MSc', 'M.Tech', 'MTech', 'MBA'
        };
        for (String prefix : degreePrefixes) {
            if (degree.toLowerCase().startsWith(prefix.toLowerCase() + ' ')) {
                return new EducationParts(prefix, cleanEducationText(degree.substring(prefix.length())));
            }
        }

        return new EducationParts(degree, '');
    }

    private String cleanDegreeName(String degree) {
        if (String.isBlank(degree)) return '';
        String normalized = cleanEducationText(degree);
        if (normalized == 'B.A') return 'B.A.';
        if (normalized == 'B.S') return 'B.S.';
        if (normalized == 'M.A') return 'M.A.';
        if (normalized == 'M.S') return 'M.S.';
        return normalized;
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
            '- For education, split degree and field of study. Example: "B.A. in Art & Design" => degree "B.A.", major "Art & Design". Store only degree/course name in degree. Store course/field in major.\n' +
            '- Education connector words include: in, for, with, major in, majoring in, majored in, specialization in, specialized in, specializing in, concentration in, concentrated in, focus in, focused in, emphasis in, option in, stream in, track in, pathway in, discipline of, field of, program in, course in, degree in, honours in, honors in, minor in, double major in. Also split on parentheses, hyphen, colon, slash, comma when used between degree and field.\n' +
            '- Do NOT create duplicate education entries for same institution + graduationYear + fieldOfStudy. If one line says "B.A. in Art & Design", return one record only: degree "B.A.", major "Art & Design". Do not also return "B.A. in Art & Design" as another degree.\n' +
            '- Extract candidate mailing address when present. Split street, city, state/province, postalCode, country.\n' +
            '- Infer missing country/state from obvious address clues. Example: "1 Crown Street\\nSydney NSW 2000" => street "1 Crown Street", city "Sydney", state "NSW", postalCode "2000", country "Australia". Australian states include NSW, VIC, QLD, SA, WA, TAS, NT, ACT.\n' +
            '- If country is missing but city/state/postcode clearly identify Australia, set country to "Australia".\n' +
            '- Extract job locations (city, state, country)\n' +
            '- Calculate total professional experience in years from work history dates and return numeric totalYearsExperience\n' +
            '- Convert job descriptions into numbered bullet points. Keep each job description under 700 characters.\n' +
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
            '    "socialProfiles": { "LinkedIn": "url", "Instagram": "url", "Facebook": "url", "SEEK": "url", "GitHub": "url", "Portfolio": "url", "Website": "url", "Other": "url" },\n' +
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
            '  "extractedText": "READABLE CV TEXT SUMMARY WITH SECTION HEADERS - max 8000 characters, preserve line breaks using \\n"\n' +
            '}\n\n' +
            'RULES:\n' +
            '1. Extract ALL jobs - this CV should have multiple positions\n' +
            '2. Extract ALL education - look for degrees, universities, graduation years\n' +
            '3. For each job, extract location (city, state, country) if mentioned\n' +
            '4. totalYearsExperience must be a number based on workHistory dates. Use decimals when needed, e.g. 3.5. If unknown, use 0\n' +
            '5. Convert job descriptions into numbered bullet points (1. 2. 3. etc.)\n' +
            '6. Use \\n to separate lines, description and sections in all text fields\n' +
            '7. Convert month names to numbers (June=06, August=08)\n' +
            '8. Use "" for missing strings, [] for missing arrays, {"city":"","state":"","country":""} for missing location\n' +
            '9. Extract all social profile links from CV into personalInfo.socialProfiles. Include LinkedIn, Instagram, Facebook, SEEK, GitHub, portfolio, website, or other profile URLs.\n' +
            '10. For extractedText: Include readable CV text, max 8000 characters. Preserve section headers and key lines only.\n' +
            '   - Preserve all section headers (e.g., "EXPERIENCE", "EDUCATION", "SKILLS")\n' +
            '   - Use \\n for line breaks\n' +
            '   - Use \\n\\n for section breaks\n' +
            '   - Preserve bullet points as "• " or "- "\n' +
            '   - Keep the original formatting structure\n' +
            '11. JSON must be complete and valid. Do not truncate arrays or strings.\n' +
            '12. Return ONLY JSON - no markdown, no explanation';
    }
    
    // ==================== HELPER METHODS ====================

    private static Blakeney_Setting__mdt getBlakeneySettings() {
        try {
            return [
                SELECT Claude_API_Key__c,
                    AWS_Access_Key__c,
                    AWS_Secret_Key__c,
                    AWS_Bucket_Name__c,
                    AWS_Host__c
                FROM Blakeney_Setting__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to get Blakeney settings: ' + e.getMessage());
            return null;
        }
    }

    private static String getClaudeAPIKey() {
        Blakeney_Setting__mdt settings = getBlakeneySettings();
        if (settings != null && String.isNotBlank(settings.Claude_API_Key__c)) {
            return settings.Claude_API_Key__c;
        }
        throw new ResumeParserConfigurationException('Claude API key not configured in Blakeney_Setting__mdt');
    }

    private static String limitErrorMessage(String value) {
        if (String.isBlank(value)) return 'No response body';
        return value.length() > 500 ? value.substring(0, 500) : value;
    }

    private static AwsSettings getAwsSettings() {
        Blakeney_Setting__mdt settings = getBlakeneySettings();
        if (settings == null ||
            String.isBlank(settings.AWS_Access_Key__c) ||
            String.isBlank(settings.AWS_Secret_Key__c)) {
            throw new ResumeParserConfigurationException('AWS credentials not configured in Blakeney_Setting__mdt');
        }

        AwsSettings awsSettings = new AwsSettings();
        awsSettings.accessKey = settings.AWS_Access_Key__c;
        awsSettings.secretKey = settings.AWS_Secret_Key__c;
        awsSettings.bucketName = String.isNotBlank(settings.AWS_Bucket_Name__c)
            ? settings.AWS_Bucket_Name__c
            : DEFAULT_AWS_BUCKET_NAME;
        awsSettings.host = String.isNotBlank(settings.AWS_Host__c)
            ? settings.AWS_Host__c
            : DEFAULT_AWS_HOST;
        return awsSettings;
    }
    
    private String getString(Map<String, Object> maps, String key) {
        Object value = maps.get(key);
        return value != null ? String.valueOf(value) : '';
    }

    private String formatSocialProfileLinks(Map<String, Object> personal) {
        if (personal == null) return null;

        Map<String, String> profiles = new Map<String, String>();
        String linkedIn = getString(personal, 'linkedIn');
        if (String.isNotBlank(linkedIn)) profiles.put('LinkedIn', linkedIn);

        Object socialObject = personal.get('socialProfiles');
        if (socialObject != null) {
            try {
                Map<String, Object> socialProfiles = (Map<String, Object>) socialObject;
                for (String label : socialProfiles.keySet()) {
                    String url = String.valueOf(socialProfiles.get(label));
                    if (String.isBlank(label) || String.isBlank(url)) continue;
                    profiles.put(normalizeSocialProfileLabel(label), url.trim());
                }
            } catch (Exception socialException) {
                System.debug('Unable to parse social profiles: ' + socialException.getMessage());
            }
        }

        List<String> lines = new List<String>();
        for (String label : new List<String>{'LinkedIn', 'Instagram', 'Facebook', 'SEEK', 'GitHub', 'Portfolio', 'Website', 'Other'}) {
            String url = profiles.get(label);
            if (String.isNotBlank(url)) lines.add(label + ' : ' + url);
        }
        for (String label : profiles.keySet()) {
            if (!new Set<String>{'LinkedIn', 'Instagram', 'Facebook', 'SEEK', 'GitHub', 'Portfolio', 'Website', 'Other'}.contains(label)) {
                String url = profiles.get(label);
                if (String.isNotBlank(url)) lines.add(label + ' : ' + url);
            }
        }
        return lines.isEmpty() ? null : String.join(lines, '\n');
    }

    private String normalizeSocialProfileLabel(String label) {
        if (String.isBlank(label)) return 'Other';
        String lowerLabel = label.trim().toLowerCase();
        if (lowerLabel.contains('linkedin')) return 'LinkedIn';
        if (lowerLabel.contains('instagram')) return 'Instagram';
        if (lowerLabel.contains('facebook')) return 'Facebook';
        if (lowerLabel.contains('seek')) return 'SEEK';
        if (lowerLabel.contains('github')) return 'GitHub';
        if (lowerLabel.contains('portfolio')) return 'Portfolio';
        if (lowerLabel.contains('website')) return 'Website';
        return label.trim();
    }

    private void applyMailingAddress(Contact con, Map<String, Object> address) {
        if (con == null || address == null) return;
        String street = getString(address, 'street');
        String city = getString(address, 'city');
        String state = normalizeAustralianState(getString(address, 'state'));
        String postalCode = getString(address, 'postalCode');
        String country = getString(address, 'country');

        if (String.isBlank(country) && isAustralianAddress(city, state, postalCode)) {
            country = 'Australia';
        }

        con.MailingStreet = street;
        con.MailingCity = city;
        con.MailingState = state;
        con.MailingPostalCode = postalCode;
        con.MailingCountry = country;
    }

    private String normalizeAustralianState(String value) {
        if (String.isBlank(value)) return value;
        String state = value.trim();
        String upperState = state.toUpperCase();
        if (upperState == 'NEW SOUTH WALES') return 'NSW';
        if (upperState == 'VICTORIA') return 'VIC';
        if (upperState == 'QUEENSLAND') return 'QLD';
        if (upperState == 'SOUTH AUSTRALIA') return 'SA';
        if (upperState == 'WESTERN AUSTRALIA') return 'WA';
        if (upperState == 'TASMANIA') return 'TAS';
        if (upperState == 'NORTHERN TERRITORY') return 'NT';
        if (upperState == 'AUSTRALIAN CAPITAL TERRITORY') return 'ACT';
        return state;
    }

    private Boolean isAustralianAddress(String city, String state, String postalCode) {
        Set<String> states = new Set<String>{'NSW', 'VIC', 'QLD', 'SA', 'WA', 'TAS', 'NT', 'ACT'};
        if (String.isNotBlank(state) && states.contains(state.trim().toUpperCase())) return true;
        if (String.isNotBlank(postalCode)) {
            String cleanPostcode = postalCode.trim();
            if (Pattern.matches('^[0-9]{4}$', cleanPostcode) && String.isNotBlank(city)) return true;
        }
        return false;
    }

    private Decimal parseDecimal(Object value) {
        if (value == null) return null;
        try {
            String text = String.valueOf(value).trim();
            if (String.isBlank(text)) return null;
            text = text.replace(',', '');
            if (text.endsWith('+')) {
                text = text.substring(0, text.length() - 1);
            }
            return Decimal.valueOf(text);
        } catch (Exception e) {
            System.debug('Error parsing decimal value: ' + String.valueOf(value));
            return null;
        }
    }

    private String normalizeKey(String value) {
        return String.isBlank(value) ? '' : value.trim().toLowerCase();
    }

    private List<String> splitSkills(String skillsText) {
        List<String> skills = new List<String>();
        if (String.isBlank(skillsText)) return skills;
        for (String rawSkill : skillsText.split('[,;\\n]+')) {
            if (String.isNotBlank(rawSkill)) {
                skills.add(rawSkill.trim());
            }
        }
        return skills;
    }

    private String mergeSkillText(String existingSkills, List<String> incomingSkills) {
        Set<String> seen = new Set<String>();
        List<String> merged = new List<String>();
        if (incomingSkills != null) {
            for (String rawSkill : incomingSkills) {
                addUniqueSkill(merged, seen, rawSkill);
            }
        }
        return merged.isEmpty() ? null : String.join(merged, ', ');
    }

    private void syncCareerIntentSkills(Id contactId, String skillsText) {
        if (contactId == null || String.isBlank(skillsText) || !Schema.getGlobalDescribe().containsKey('Career_Intent__c')) return;

        try {
            List<Career_Intent__c> intents = [
                SELECT Id, Skills__c
                FROM Career_Intent__c
                WHERE Contact__c = :contactId OR Candidate__c = :contactId
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            Career_Intent__c intent = intents.isEmpty()
                ? new Career_Intent__c(Contact__c = contactId, Candidate__c = contactId)
                : intents[0];
            String mergedSkills = mergeSkillText(null, splitSkills(skillsText));
            if (String.isBlank(mergedSkills) || intent.Skills__c == mergedSkills) return;

            intent.Skills__c = mergedSkills;
            if (intent.Id == null) insert intent;
            else update intent;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Unable to sync Career Intent skills: ' + e.getMessage());
        }
    }

    private void addUniqueSkill(List<String> merged, Set<String> seen, String rawSkill) {
        String cleaned = rawSkill == null ? '' : rawSkill.trim();
        if (String.isBlank(cleaned)) return;
        String key = cleaned.toLowerCase();
        if (seen.contains(key)) return;
        seen.add(key);
        merged.add(cleaned);
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

    public class AwsSettings {
        public String accessKey;
        public String secretKey;
        public String bucketName;
        public String host;
    }

    global class UploadResult {
        global Boolean success;
        global String message;
        global Id contactId;
        global Map<String, Object> data;
    }

    public class ResumeParserConfigurationException extends Exception {}
}