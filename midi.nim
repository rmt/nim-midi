when defined(LINUX) or defined(JACK):
  include jackmidi
else:
  when defined(WINDOWS):
    {.error: "Windows is not yet supported." .}
  when defined(DARWIN):
    {.error: "Darwin is not yet supported." .}
  {.error: "Your OS is not yet supported." .}
