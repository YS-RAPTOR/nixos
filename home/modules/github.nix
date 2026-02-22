{ settings, ... }:
{
    programs.git = {
        enable = true;
        settings = {
            user = {
                name = settings.user.github-username;
                email = settings.user.email;
            };
            url = {
                "git@github.com:" = {
                    insteadOf = "https://github.com/";
                };
            };
        };
    };
}
