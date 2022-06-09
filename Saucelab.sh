set -e
set -x

       cd /Users/runner/work/splunk-otel-ios/splunk-otel-ios/
          ls
          curl -u "sso-splunk.saucelabs.com-mahimag:274c9a94-86d1-4b12-9594-57307cfb2c57" --location \
             --request POST 'https://api.us-west-1.saucelabs.com/v1/storage/upload' \
             --form 'payload=@"SmokeTest.zip"' \
             --form 'name="SmokeTest.zip"' \
             --form 'description="iOS Test App v3"'
