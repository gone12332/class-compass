// Class Compass settings for anonymous stats and the /admin page.
// Paste the two values from Supabase: Project Settings > API (or Data API).
// The anon key is meant to be public. It can only call cc_track(); it can't read or change your data.
// Leave both empty to turn stats off.
window.CC_CONFIG = {
  supabaseUrl: "",
  supabaseAnonKey: ""
};
