. helpers.sh

start_test_server \
  -line 1 -file data/require-proxyauth-digest \
  -line 10 -expect-re 'Proxy-Authorization: Digest username="testuser",realm="testrealm",nonce="948647427",uri="http://localhost:[0-9]+/",response="[0-9a-f]+",algorithm=MD5' \
  -line 10 -file data/framed
trap "stop_test_server" EXIT
request \
  -proxy -proxy-user testuser -proxy-password testpassword \
  -get / \
  -run
