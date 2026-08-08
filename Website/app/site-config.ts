type DownloadChannel = {
  enabled: boolean;
  href: string;
  label: string;
};

const repositoryURL = "https://github.com/Kyle-Ye/SwiftyDownloadManager";

export const siteConfig: {
  repositoryURL: string;
  licenseURL: string;
  downloads: {
    github: DownloadChannel;
    appStore: DownloadChannel;
  };
} = {
  repositoryURL,
  licenseURL: `${repositoryURL}/blob/main/LICENSE.md`,
  downloads: {
    github: {
      enabled: true,
      href: `${repositoryURL}/releases/latest`,
      label: "Download Latest Version",
    },
    // Add the public App Store URL and enable this channel when the listing is ready.
    appStore: {
      enabled: false,
      href: "",
      label: "Download on the App Store",
    },
  },
};
