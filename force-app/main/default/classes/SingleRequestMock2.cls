@isTest
global class SingleRequestMock2 implements HttpCalloutMock {
    
    
    global HttpResponse respond(HTTPRequest req) {
        system.debug('req.getEndpoint() ::::::::::::::' + req.getEndpoint());
        if(req.getEndpoint() == 'https://testusername.com/api/v1/user/?limit=100&offset=0&format=json'){
            System.debug('Inside IFFFFFF :::::::::::::::::::::::::::');
            String username = 'thanhtruong217@gmail.com';
            String password = 'admin12!';
            //String body = null;
            String body = '{"meta": {"limit": 20, "next": "/api/v1/user/?offset=20&limit=20&format=json", "offset": 0, "previous": null, "total_count": 389}, "objects": [{"address": "", "company": "", "concurrent_call_limit": 8, "credit": "13.0000", "email": "", "first_name": "Mark", "last_credit_purchase_date": "", "last_credit_usage_date": "", "last_name": "Richards", "last_purchase": 20, "ll_sms": 0, "ll_vm": 0, "lll_sms": 0, "lll_vm": 739, "lm_sms": 0, "lm_voicemail": 0, "phone": "0416828575", "resource_uri": "/api/v1/user/397/", "scheduler_email_cdr_report": "daily", "sms": 0, "sms_mask": "", "status": "Trial Customer", "sure_name": "", "timezone": "Australia/Sydney", "voicemail": 0, "weekly_low_balance_notification": false}]}';
                Blob headerValue = Blob.valueOf( username + ':' + password);
            
            String authorizationHeader = 'Basic ' +
                EncodingUtil.base64Encode(headerValue);
            String contentType = 'application/x-www-form-urlencoded' ;
            HttpResponse resp = new HttpResponse();
            
            resp.setHeader('Authorization', authorizationHeader);
            resp.setHeader('Content-Type', contentType);
            resp.setStatusCode(200);
            resp.setBody(body);
            return resp;
        }else{
            String username = 'thanhtruong217@gmail.com';
            String password = 'admin12!';
            //String body = 'null';
            String body = '{"meta": {"limit": 20, "next": "/api/v1/user/?offset=20&limit=20&format=json", "offset": 0, "previous": null, "total_count": 389}, "objects": [{"address": "", "company": "", "concurrent_call_limit": 8, "credit": "13.0000", "email": "", "first_name": "Mark", "last_credit_purchase_date": "2016-12-12 11:17:20.177000+00:00", "last_credit_usage_date": "2017-09-19 04:38:40.153127+00:00", "last_name": "Richards", "last_purchase": 20, "ll_sms": 0, "ll_vm": 0, "lll_sms": 0, "lll_vm": 739, "lm_sms": 0, "lm_voicemail": 0, "phone": "0416828575", "resource_uri": "/api/v1/user/397/", "scheduler_email_cdr_report": "daily", "sms": 0, "sms_mask": "", "status": "Trial Customer", "sure_name": "", "timezone": "Australia/Sydney", "voicemail": 0, "weekly_low_balance_notification": false}]}';
            Blob headerValue = Blob.valueOf( username + ':' + password);
            
            String authorizationHeader = 'Basic ' +
                EncodingUtil.base64Encode(headerValue);
            String contentType = 'application/x-www-form-urlencoded' ;
            HttpResponse resp = new HttpResponse();
            
            resp.setHeader('Authorization', authorizationHeader);
            resp.setHeader('Content-Type', contentType);
            resp.setStatusCode(200);
            resp.setBody(body);
            
            return resp;    
        }
        
    }
    
}