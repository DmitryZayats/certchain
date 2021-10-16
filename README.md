# certchain
Certificate chain creation. Script will create Root CA, Intermediate CA, generate CSR and sign it with Intermediate CA.

This project aims at automating certificate chain Creation for tomcat as much as possible.
The goal is not to use self signed certificate for securing tomcat and then testing client/server 
communication with this self signed certificate, but instead generate:  
- Root CA
- Intermediate CA
- Server certificate  

And then use these certificates when doing internal lab testing of SSO (SAML).  

Certificate creation will be done with the help of ubuntu:18.04 docker container to minimize impact of environment difference.  

This document is inspired by [OpenSSL Certificate Authority](https://jamielinux.com/docs/openssl-certificate-authority/index.html)

## Start ubuntu 18.04 docker container and prepare environment

```
docker run -d -ti --name=certchain ubuntu:18.04 /bin/bash
docker exec -ti certchain /bin/bash
cd
apt update
apt install git -y
apt install openjdk-11-jre-headless -y
```

## Clone this git repository and run certificate chain creation script

```

```

Script CreateCertChain.sh for creating certificate chain has configurable variables on lines 9-16.   
If you don't modify any of those variables - sever certificate will be generated for CN=tomcat1.lab.net  
and alias of the private key and attached certificate chain will be set to tomcat1  
Most likely you would need to change below 3 parameters:
- ServerName. To reflect FQDN name of your server.  
- keystorealias. To change alias that contains private key and certificate chain in the keystore.jks file.  
- truststorealias. This is alias for Root CA in the truststore.jks file.  

When executing script you will need to answer "yes" several times to confirmation dialogues and enter keystore and truststore passwords for your new keystore and truststore.  

```
cd certchain
chmod u+x CreateCertChain.sh
./CreateCertChain.sh
```

## Exit container and fetch generated files 

As a result of script execution a number of files have been generated inside container file system.  
Below table gives explanation of each file and command to fetch it.  

|File Name inside container|Meaning|Command to fetch|
|--------------------------|-------|----------------|
|/root/ca/intermediate/keystore.jks|This is a keystore file that needs to be used by tomcat. This file contains server private key, associated server certificate and intermediate certificate. As a result of such setup - tomcat will be reporting server cert and intermediate cert. Root CA will not be reported. For this reason it's important that client has imported Root CA into its truststore.|docker cp certchain:/root/ca/intermediate/keystore.jks ./|
|/root/ca/truststore.jks|This is truststore which contains Root CA. This is not strictly needed for testing SAML as in the SAML testing we need to use /root/ca/certs/ca.cert.pem in the base64 format and insert it into kubernetes secret. But more about this later.|docker cp certchain:/root/ca/truststore.jks ./|
|/root/ca/certs/ca.cert.pem|This is a Root CA, aka Certificate Authority certificate. This certificate is imported into truststore.jks and is used by demo application.| docker cp certchain:/root/ca/certs/ca.cert.pem ./|
|/root/ca/intermediate/certs/intermediate.cert.pem|This is intermediate CA. This pem is used in the keystore.jks file|docker cp certchain:/root/ca/intermediate/certs/intermediate.cert.pem ./|
|/root/ca/intermediate/certs/tomcat1.lab.net.cert.pem|Name of this file depends on your server CN. This is a server certificate in the pem format. Used in the keystore.jks file|docker cp certchain:/root/ca/intermediate/certs/tomcat1.lab.net.cert.pem ./|
|/root/ca/intermediate/private/tomcat1.lab.net.key.pem|Name of this file depends on your server CN. This is a server private key in the pem format. Used in the keystore.jks file|docker cp certchain:/root/ca/intermediate/private/tomcat1.lab.net.key.pem ./|

In the below example I'm creating separate directory which will be holding certificate chain files.

```
mkdir ~/Downloads/docker_volumes/tomcat4
cd ~/Downloads/docker_volumes/tomcat4
docker cp certchain:/root/ca/intermediate/keystore.jks ./
docker cp certchain:/root/ca/truststore.jks ./
docker cp certchain:/root/ca/certs/ca.cert.pem ./
docker cp certchain:/root/ca/intermediate/certs/intermediate.cert.pem ./
docker cp certchain:/root/ca/intermediate/certs/tomcat1.lab.net.cert.pem ./
```

## Start new tomcat docker and test communication via TLS with the docker

To enable TLS in tomcat we need to append to tomcat server.xml file this fragment.
When adding this fragment pay close attention to keyAlias and keystorePass.  
These 2 parameters need to be matched with the keystorealias value from the certificate chain creation script and password that was entered when keystore.jks was created.

```
           <Connector port="8443"
           protocol="org.apache.coyote.http11.Http11NioProtocol"
           clientAuth="false"
           sslProtocol="TLSv1.2, TLSv1.3"
           ciphers="ECDHE-ECDSA-AES128-GCM-SHA256,ECDHE-RSA-AES128-GCM-SHA256,ECDHE-ECDSA-AES256-GCM-SHA384,ECDHE-RSA-AES256-GCM-SHA384,ECDHE-ECDSA-CHACHA20-POLY1305,ECDHE-RSA-CHACHA20-POLY1305,DHE-RSA-AES128-GCM-SHA256,DHE-RSA-AES256-GCM-SHA384"
           maxThreads="150"
           enableLookups="false"
           disableUploadTimeout="true"
           acceptCount="100"
           scheme="https"
           secure="true"
           SSLEnabled="true"
           keystoreFile="${catalina.base}/conf/keystore.jks"
           keyAlias="tomcat1"
           keystorePass="changeme"
           />
```

The simplest way is to start new tomcat container, copy default server.xml from this container to your local file system, add changes and then use server.xml file as overlay.

```
cd ~/Downloads/docker_volumes/tomcat4
docker run -ti -d --rm --name=temptomcat tomcat
docker cp temptomcat:/usr/local/tomcat/conf/server.xml ./
docker stop temptomcat
```

Make changes to server.xml and now use this server.xml to start new tomcat. Adjust below command to your environment as we need to use absolute path when mounting local file system.

```
docker run -it -d --rm -p 9080:8080 -p 9443:8443 \
-v /home/dmitry/Downloads/docker_volumes/tomcat4/server.xml:/usr/local/tomcat/conf/server.xml \
-v /home/dmitry/Downloads/docker_volumes/tomcat4/keystore.jks:/usr/local/tomcat/conf/keystore.jks \
-v /home/dmitry/Downloads/docker_volumes/tomcat4/server.truststore:/usr/local/tomcat/conf/server.truststore \
tomcat
```

We can now test communication with the tomcat container via browser and examine certificate reported by tomcat.  
Another test is a simple java tls client replicating saml-agent code.  
In the below example we can see that when certificate store is not loaded - we get 

```
------------------------< com.nokia:sslclient >-------------------------
Building sslclient 1.0-SNAPSHOT
--------------------------------[ jar ]---------------------------------

--- exec-maven-plugin:1.5.0:exec (default-cli) @ sslclient ---
Making Get request to https://tomcat1.lab.net:9443/samlagent-1.0-SNAPSHOT/Hello
Exception in thread "main" javax.net.ssl.SSLException: Unexpected error: java.security.InvalidAlgorithmParameterException: the trustAnchors parameter must be non-empty
```

And when we are loading truststore - we are able to communicate with the tomcat server successfully.  
Response 404 comes from the fact that there are no apps deployed on this tomcat at the moment.

```
------------------------< com.nokia:sslclient >-------------------------
Building sslclient 1.0-SNAPSHOT
--------------------------------[ jar ]---------------------------------

--- exec-maven-plugin:1.5.0:exec (default-cli) @ sslclient ---
Making Get request to https://tomcat1.lab.net:9443/samlagent-1.0-SNAPSHOT/Hello
GET Response Status:: 404
------------------------------------------------------------------------
BUILD SUCCESS
```

Simple ssl java client.  

```java
 public static void main(String[] args) throws KeyStoreException, NoSuchAlgorithmException, KeyManagementException, IOException, CertificateException {
        // TODO code application logic here
        
        SSLConnectionSocketFactory sslConnectionFactory = null;
        SSLContext sslcontext = null;
        String truststorePass = "changeme";
        String trustStoreFile = "/home/dmitry/Downloads/docker_volumes/tomcat4/truststore.jks";
        String GET_URL = "https://tomcat1.lab.net:9443";
        System.out.println("Making Get request to " + GET_URL);
        BasicHttpClientConnectionManager connManager;
        
        KeyStore trustStore  = KeyStore.getInstance(KeyStore.getDefaultType());
        
//        ### Below 2 lines actually load trust store ############################
        java.io.FileInputStream fis = new java.io.FileInputStream(trustStoreFile);
        trustStore.load(fis, truststorePass.toCharArray());
//        ########################################################################
            
            sslcontext = SSLContexts.custom()
            .loadTrustMaterial(trustStore, new TrustSelfSignedStrategy())
            .build();
            sslConnectionFactory = new SSLConnectionSocketFactory(sslcontext,
            		new DefaultHostnameVerifier());
        
        connManager = new BasicHttpClientConnectionManager(
               RegistryBuilder.<ConnectionSocketFactory>create()
                   .register("https",sslConnectionFactory )
                   .build(), null, null, null);
        
        CloseableHttpClient httpclient = HttpClients.custom()
        		 .setConnectionManager(connManager)
                .build();
        
        HttpGet httpGet = new HttpGet(GET_URL);
        
        CloseableHttpResponse httpResponse = httpclient.execute(httpGet);
        
        System.out.println("GET Response Status:: "
				+ httpResponse.getStatusLine().getStatusCode());
        
    }
```
