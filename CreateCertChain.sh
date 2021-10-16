#/bin/bash
##############################################################################
#
# Script to generate Certificate Chain for use with Tomcat
#
##############################################################################

### Set your variables here ###
CAName="Root CA"
CAsubject="/C=US/ST=IL/L=Chicago/O=SomeCompany/OU=SomeUnit/CN=$CAName"
IntermediateName="Intermediate"
IntermediateSubject="/C=US/ST=IL/L=Chicago/O=SomeCompany/OU=SomeUnit/CN=$IntermediateName"
ServerName="frontend.lab.net"
ServerSubject="/C=US/ST=IL/L=Chicago/O=HornsAndHoves/OU=Marketing/CN=$ServerName"
keystorealias="tomcat1"
truststorealias="rootca"
##############################################################################


### Create directory structure
mkdir /root/ca
mkdir /root/ca/certs /root/ca/crl /root/ca/newcerts /root/ca/private
mkdir /root/ca/intermediate
mkdir /root/ca/intermediate/certs /root/ca/intermediate/crl /root/ca/intermediate/csr /root/ca/intermediate/newcerts /root/ca/intermediate/private
### Copy root config openssl.conf from repo to directory structure
cp root-config-openssl.cnf /root/ca/openssl.cnf
cp intermediate-config-openssl.cnf /root/ca/intermediate/openssl.cnf
cp server-openssl.cnf /root/ca/intermediate/server-openssl.cnf
### Change persissions
cd /root/ca
chmod 700 private
touch index.txt
echo 1000 > serial
### Generate private key (Note that I'm not securing it with the key to allow for fully automated process)
#openssl genrsa -aes256 -out private/ca.key.pem 4096
openssl genrsa -out private/ca.key.pem 4096
chmod 400 private/ca.key.pem
### Generate Root CA
openssl req -config openssl.cnf \
      -key private/ca.key.pem \
      -new -x509 -days 7300 -sha256 -extensions v3_ca \
      -out certs/ca.cert.pem -subj "$CAsubject"
chmod 444 certs/ca.cert.pem
### Now generate intermediate private key (Note that I'm not securing it with the key to allow for fully automated process)
cd /root/ca/intermediate
chmod 700 private
touch index.txt
echo 1000 > serial
echo 1000 > /root/ca/intermediate/crlnumber
cd /root/ca
#openssl genrsa -aes256 -out intermediate/private/intermediate.key.pem 4096
openssl genrsa -out intermediate/private/intermediate.key.pem 4096
chmod 400 intermediate/private/intermediate.key.pem
### Generate intermediate CSR
cd /root/ca
openssl req -config intermediate/openssl.cnf -new -sha256 \
      -key intermediate/private/intermediate.key.pem \
      -out intermediate/csr/intermediate.csr.pem -subj "$IntermediateSubject"
### Sign intermediate CSR with root CA
cd /root/ca
openssl ca -config openssl.cnf -extensions v3_intermediate_ca \
      -days 3650 -notext -md sha256 \
      -in intermediate/csr/intermediate.csr.pem \
      -out intermediate/certs/intermediate.cert.pem
chmod 444 intermediate/certs/intermediate.cert.pem
### Generate private key for server certificate (Note that I'm not securing it with the key to allow for fully automated process)
cd /root/ca
openssl genrsa \
      -out intermediate/private/${ServerName}.key.pem 2048
chmod 400 intermediate/private/${ServerName}.key.pem
### Create CSR
cd /root/ca
openssl req -config intermediate/server-openssl.cnf \
      -key intermediate/private/${ServerName}.key.pem \
      -new -sha256 -out intermediate/csr/${ServerName}.csr.pem -subj "$ServerSubject"
### Sign CSR
cd /root/ca
openssl ca -config intermediate/openssl.cnf \
      -extensions server_cert -days 375 -notext -md sha256 \
      -in intermediate/csr/${ServerName}.csr.pem \
      -out intermediate/certs/${ServerName}.cert.pem
chmod 444 intermediate/certs/${ServerName}.cert.pem
### Now combine server key, server cert and intermediate cert into one pem file and create keystore out of it
cat /root/ca/intermediate/certs/tomcat1.lab.net.cert.pem /root/ca/intermediate/certs/intermediate.cert.pem /root/ca/intermediate/private/tomcat1.lab.net.key.pem > /root/ca/intermediate/keystore.pem
echo "Now you will need to enter password for keystore, which will be created from server key, server cert and intermediate cert"
openssl pkcs12 -export -in /root/ca/intermediate/keystore.pem -out /root/ca/intermediate/keystore.jks -name ${keystorealias}
### Create trust store out of root CA
cd /root/ca
echo "Now you will need to enter password for the truststore.jks file which will be created based on Root CA certificate"
keytool -import -alias ${truststorealias} -file /root/ca/certs/ca.cert.pem -keystore truststore.jks
