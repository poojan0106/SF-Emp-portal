@RestResource(urlMapping='/candidate/cv/upload')
global with sharing class CandidateCVUploadRestResource {
    global class UploadRequest {
        public String contactId;
        public String fileName;
        public String base64Content;
        public String contentType;
    }

    @HttpPost
    global static void upload() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        try {
            UploadRequest payload = (UploadRequest) JSON.deserialize(request.requestBody.toString(), UploadRequest.class);
            resumeParserEmailService.UploadResult result;
            if (payload == null) {
                result = new resumeParserEmailService.UploadResult();
                result.success = false;
                result.message = 'Missing payload';
                response.statusCode = 400;
                response.responseBody = Blob.valueOf(JSON.serialize(result));
                return;
            }

            result = resumeParserEmailService.parseUploadedResumeForContact(
                (Id) payload.contactId,
                payload.fileName,
                payload.base64Content,
                payload.contentType
            );
            response.statusCode = result.success == true ? 200 : 400;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        } catch (Exception e) {
            resumeParserEmailService.UploadResult result = new resumeParserEmailService.UploadResult();
            result.success = false;
            result.message = 'CV upload failed: ' + e.getMessage();
            response.statusCode = 500;
            response.responseBody = Blob.valueOf(JSON.serialize(result));
        }
    }
}
