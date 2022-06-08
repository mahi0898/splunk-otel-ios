set -e
set -x
      uses: actions/upload-artifact@v3
         with:
          name: SmokeTest
          path: /Users/runner/work/splunk-otel-ios/splunk-otel-ios/SmokeTest.zip
