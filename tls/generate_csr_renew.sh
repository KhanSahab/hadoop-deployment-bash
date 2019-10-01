#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright Clairvoyant 2019

PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin

# ARGV:
# 1 - TLS certificate Common Name - required
# 2 - JKS store password - required
# 3 - JKS key password (should be the same as JKS store password) - required
# 4 - Extra parameters for keytool (ie Subject Alternative Name (SAN)) - optional

# generate new alternative certificate
# upgrade cert
# install renewed cert

echo "********************************************************************************"
echo "*** $(basename "$0")"
echo "********************************************************************************"
#"CN=cmhost.sec.cloudera.com,OU=Support,O=Cloudera,L=Denver,ST=Colorado,C=US"
DN="$1"
SP="$2"
#KP="$3"
KP="$SP"
#"SAN=DNS:`hostname`,DNS:my-lb.domain.com"
EXT="$4"
if [ -z "$DN" ]; then
  echo "ERROR: Missing distinguished name."
  exit 1
fi
if [ -z "$SP" ]; then
  echo "ERROR: Missing keystore password."
  exit 2
fi
if [ -z "$KP" ]; then
  echo "ERROR: Missing private key password."
  exit 3
fi
if [ -n "$EXT" ]; then
  EXT="-ext $EXT"
fi

echo "Generating TLS CSR..."
if [ -f /etc/profile.d/jdk.sh ]; then
  # shellcheck source=/dev/null
  . /etc/profile.d/jdk.sh
elif [ -f /etc/profile.d/java.sh ]; then
  # shellcheck source=/dev/null
  . /etc/profile.d/java.sh
fi

if [ ! -f /opt/cloudera/security/jks/localhost-keystore.jks ]; then
  echo "ERROR: Primary keystore does not exist.  Run 'generate_csr.sh'.  Exiting..."
  exit 10
fi

if [ -f /opt/cloudera/security/jks/localhost_renew-keystore.jks ]; then
  echo "ERROR: New keystore already exists.  Exiting..."
  exit 1
fi
keytool -genkeypair -alias localhost -keyalg RSA -sigalg SHA256withRSA \
 -keystore /opt/cloudera/security/jks/localhost_renew-keystore.jks \
 -keysize 2048 -dname "$DN" -storepass "$SP" -keypass "$KP"
chmod 0440 /opt/cloudera/security/jks/localhost_renew-keystore.jks
chown root:cloudera-scm /opt/cloudera/security/jks/localhost_renew-keystore.jks

if [ -f /opt/cloudera/security/x509/localhost_renew.csr ]; then
  echo "ERROR: New CSR already exists.  Exiting..."
  exit 2
fi
# https://www.cloudera.com/documentation/enterprise/5-9-x/topics/cm_sg_create_deploy_certs.html#concept_frd_1px_nw
# X509v3 Extended Key Usage:
#   TLS Web Server Authentication, TLS Web Client Authentication
# shellcheck disable=SC2086
keytool -certreq -alias localhost \
 -keystore /opt/cloudera/security/jks/localhost_renew-keystore.jks \
 -file /opt/cloudera/security/x509/localhost_renew.csr -storepass "$SP" \
 -keypass "$KP" -ext EKU=serverAuth,clientAuth -ext KU=digitalSignature,keyEncipherment $EXT
chmod 0444 /opt/cloudera/security/x509/localhost_renew.csr

rm -f /tmp/localhost_renew-keystore.p12.$$
keytool -importkeystore -srckeystore /opt/cloudera/security/jks/localhost_renew-keystore.jks \
 -srcstorepass "$SP" -srckeypass "$KP" -destkeystore /tmp/localhost_renew-keystore.p12.$$ \
 -deststoretype PKCS12 -srcalias localhost -deststorepass "$SP" -destkeypass "$KP"
if [ -f /opt/cloudera/security/x509/localhost_renew.e.key ]; then
  echo "ERROR: New encrypted Key already exists.  Exiting..."
  rm -f /tmp/localhost-keystore_renew.p12.$$
  exit 3
fi
openssl pkcs12 -in /tmp/localhost_renew-keystore.p12.$$ -passin "pass:$KP" -nocerts \
 -out /opt/cloudera/security/x509/localhost_renew.e.key -passout "pass:$KP"
chmod 0400 /opt/cloudera/security/x509/localhost_renew.e.key
rm -f /tmp/localhost_renew-keystore.p12.$$

if [ -f /opt/cloudera/security/x509/localhost_renew.key ]; then
  echo "ERROR: New key already exists.  Exiting..."
  exit 4
fi
openssl rsa -in /opt/cloudera/security/x509/localhost_renew.e.key \
 -passin "pass:$KP" -out /opt/cloudera/security/x509/localhost_renew.key
chmod 0400 /opt/cloudera/security/x509/localhost_renew.key

if [ -f /etc/cloudera-scm-agent/agentkey_renew.pw ]; then
  echo "ERROR: New agent PW already exists.  Exiting..."
  exit 5
fi
install -o root -g root -m 0755 -d /etc/cloudera-scm-agent
install -o root -g root -m 0600 /dev/null /etc/cloudera-scm-agent/agentkey_renew.pw
echo "$SP" >/etc/cloudera-scm-agent/agentkey_renew.pw

