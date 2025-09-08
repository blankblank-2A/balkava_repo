#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <curl/curl.h>

// you can change the fake website into real malicious websites
// also don't forget to change PHISHING_SITES_COUNT incase you add more sites

#define PHISHING_SITES_COUNT 5

const char *phishing_sites[PHISHING_SITES_COUNT] = {
    "badsite.com",
    "phishingscam.org",
    "malicious.net",
    "fakebank.com",
    "hackertrick.org"
};

// callback for writing fetched data (we just discard, no JS execution)
size_t write_callback(void *ptr, size_t size, size_t nmemb, void *userdata) {
    return size * nmemb;
}

// check for phishing
int check_phishing(const char *url) {
    for(int i=0;i<PHISHING_SITES_COUNT;i++) {
        if(strstr(url, phishing_sites[i]) != NULL)
            return 1;
    }
    return 0;
}

// check protocol and warn if HTTP
void check_protocol(const char *url) {
    if(strncmp(url, "http://", 7) == 0)
        printf("⚠ WARNING: Connection is not secure (HTTP)\n");
    else if(strncmp(url, "https://", 8) == 0)
        printf("✅ Secure connection (HTTPS)\n");
    else
        printf("⚠ WARNING: Unknown or missing protocol, assuming HTTP\n");
}

// browse website using libcurl
void browse(const char *url) {
    check_protocol(url);

    if(check_phishing(url)) {
        printf("🚨 PHISHING ALERT! Site blocked: %s\n", url);
        return;
    }

    CURL *curl = curl_easy_init();
    if(curl) {
        CURLcode res;
        curl_easy_setopt(curl, CURLOPT_URL, url);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L); // follow redirects
        curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);  // verify HTTPS cert
        curl_easy_setopt(curl, CURLOPT_USERAGENT, "BalkavaBrowser/1.0 (OPSEC Mode)");

        printf("Loading %s ...\n", url);
        res = curl_easy_perform(curl);
        if(res != CURLE_OK) {
            fprintf(stderr, "❌ Failed to fetch page: %s\n", curl_easy_strerror(res));
        } else {
            printf("[+] Page loaded successfully (JS disabled\n");
        }

        curl_easy_cleanup(curl);
    } else {
        printf("❌ Failed to initialize browser\n");
    }
}

int main() {
    char url[512];

    printf("=== Balkava Browser v2.0 ===\n");
    printf("OPSEC-lite mode: JS Disabled, Safe Browsing Enabled\n\n");

    while(1) {
        printf("Enter URL (or 'q' to quit): ");
        scanf("%511s", url);

        if(strcmp(url, "q") == 0) {
            printf("Exiting Balkava Browser... Stay safe\n");
            break;
        }

        // Add "http://" if missing
        if(strncmp(url, "http://", 7) != 0 && strncmp(url, "https://", 8) != 0) {
            char temp[520];
            snprintf(temp, sizeof(temp), "http://%s", url);
            strcpy(url, temp);
        }

        browse(url);
        printf("\n");
    }

    return 0;
}