{
  aruba = {
    dependencies = ["childprocess" "contracts" "cucumber" "rspec-expectations" "thor"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0fjqhfjkx27h4p8nrhw7snaa4inn3pvjprha5iimjkzhw00xkgbm";
      type = "gem";
    };
    version = "2.1.0";
  };
  ast = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "04nc8x27hlzlrr5c2gn7mar4vdr0apw5xg22wp6m8dx3wqr04a0y";
      type = "gem";
    };
    version = "2.4.2";
  };
  bashcov = {
    dependencies = ["simplecov"];
    groups = ["default"];
    platforms = [];
    source = {
      path = ./.;
      type = "path";
    };
    version = "3.0.3";
  };
  builder = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "045wzckxpwcqzrjr353cxnyaxgf0qg22jh00dcx7z38cys5g1jlr";
      type = "gem";
    };
    version = "3.2.4";
  };
  bundler-audit = {
    dependencies = ["thor"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0gdx0019vj04n1512shhdx7hwphzqmdpw4vva2k551nd47y1dixx";
      type = "gem";
    };
    version = "0.9.1";
  };
  childprocess = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1lvcp8bsd35g57f7wz4jigcw2sryzzwrpcgjwwf3chmjrjcww5in";
      type = "gem";
    };
    version = "4.1.0";
  };
  contracts = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0gfybfsb6kqxvvcrv1q7bfjaxmq73pf3vqy4bbzarkbajil05ii5";
      type = "gem";
    };
    version = "0.17";
  };
  cucumber = {
    dependencies = ["builder" "cucumber-ci-environment" "cucumber-core" "cucumber-cucumber-expressions" "cucumber-gherkin" "cucumber-html-formatter" "cucumber-messages" "diff-lcs" "mime-types" "multi_test" "sys-uname"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1ahpifcqv0h5r9cgd97fwr73ps90h50jzi0h17zsaw4ksb3b6g2m";
      type = "gem";
    };
    version = "8.0.0";
  };
  cucumber-ci-environment = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0a11b6w6khjb7rw7ksxdw4bprmg9gfc8xdrsbgv8767ri891s4lq";
      type = "gem";
    };
    version = "9.2.0";
  };
  cucumber-core = {
    dependencies = ["cucumber-gherkin" "cucumber-messages" "cucumber-tag-expressions"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0drg9w5cz5mchh077y9ixsy7yiyrzg3cqc29mmkl3vjcwlkhn3rh";
      type = "gem";
    };
    version = "11.0.0";
  };
  cucumber-cucumber-expressions = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "14xkgpy69p24winh4p5q2b3534i02xxbxl5rn0capqv97qjyj63j";
      type = "gem";
    };
    version = "15.2.0";
  };
  cucumber-gherkin = {
    dependencies = ["cucumber-messages"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0dsvcjy78c114q3znacs25zhq3f49q9kkxq4j9iw8b6kwimrl8wj";
      type = "gem";
    };
    version = "23.0.1";
  };
  cucumber-html-formatter = {
    dependencies = ["cucumber-messages"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1gnmm1r4gyqqwzx482zsbahjyamnj0lxxky86zs4a376jv9bicyz";
      type = "gem";
    };
    version = "19.2.0";
  };
  cucumber-messages = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1i8abkxykq7ab15pirrrf0jz9200i3x3pda2ffyxmck6063lyjgv";
      type = "gem";
    };
    version = "18.0.0";
  };
  cucumber-tag-expressions = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0v1ssg4chkahck1ddl2j1hcifm0vlcn9sb104ywshw5gyv59s9qd";
      type = "gem";
    };
    version = "4.1.0";
  };
  diff-lcs = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0rwvjahnp7cpmracd8x732rjgnilqv2sx7d1gfrysslc3h039fa9";
      type = "gem";
    };
    version = "1.5.0";
  };
  docile = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1lxqxgq71rqwj1lpl9q1mbhhhhhhdkkj7my341f2889pwayk85sz";
      type = "gem";
    };
    version = "1.4.0";
  };
  ffi = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1862ydmclzy1a0cjbvm8dz7847d9rch495ib0zb64y84d3xd4bkg";
      type = "gem";
    };
    version = "1.15.5";
  };
  json = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0nalhin1gda4v8ybk6lq8f407cgfrj6qzn234yra4ipkmlbfmal6";
      type = "gem";
    };
    version = "2.6.3";
  };
  language_server-protocol = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0gvb1j8xsqxms9mww01rmdl78zkd72zgxaap56bhv8j45z05hp1x";
      type = "gem";
    };
    version = "3.17.0.3";
  };
  mime-types = {
    dependencies = ["mime-types-data"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0ipw892jbksbxxcrlx9g5ljq60qx47pm24ywgfbyjskbcl78pkvb";
      type = "gem";
    };
    version = "3.4.1";
  };
  mime-types-data = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1pky3vzaxlgm9gw5wlqwwi7wsw3jrglrfflrppvvnsrlaiz043z9";
      type = "gem";
    };
    version = "3.2023.0218.1";
  };
  multi_test = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "042d6a1416h3di57z107ygmjdgacrpyswi73ryz75yv3v36m1rg9";
      type = "gem";
    };
    version = "1.1.0";
  };
  parallel = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0jcc512l38c0c163ni3jgskvq1vc3mr8ly5pvjijzwvfml9lf597";
      type = "gem";
    };
    version = "1.23.0";
  };
  parser = {
    dependencies = ["ast" "racc"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1swigds85jddb5gshll1g8lkmbcgbcp9bi1d4nigwvxki8smys0h";
      type = "gem";
    };
    version = "3.2.2.3";
  };
  racc = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "11v3l46mwnlzlc371wr3x6yylpgafgwdf0q7hc7c1lzx6r414r5g";
      type = "gem";
    };
    version = "1.7.1";
  };
  rainbow = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0smwg4mii0fm38pyb5fddbmrdpifwv22zv3d3px2xx497am93503";
      type = "gem";
    };
    version = "3.1.1";
  };
  rake = {
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "15whn7p9nrkxangbs9hh75q585yfn66lv0v2mhj6q6dl6x8bzr2w";
      type = "gem";
    };
    version = "13.0.6";
  };
  regexp_parser = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "136br91alxdwh1s85z912dwz23qlhm212vy6i3wkinz3z8mkxxl3";
      type = "gem";
    };
    version = "2.8.1";
  };
  rexml = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "05i8518ay14kjbma550mv0jm8a6di8yp5phzrd8rj44z9qnrlrp0";
      type = "gem";
    };
    version = "3.2.6";
  };
  rspec = {
    dependencies = ["rspec-core" "rspec-expectations" "rspec-mocks"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "171rc90vcgjl8p1bdrqa92ymrj8a87qf6w20x05xq29mljcigi6c";
      type = "gem";
    };
    version = "3.12.0";
  };
  rspec-core = {
    dependencies = ["rspec-support"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0l95bnjxdabrn79hwdhn2q1n7mn26pj7y1w5660v5qi81x458nqm";
      type = "gem";
    };
    version = "3.12.2";
  };
  rspec-expectations = {
    dependencies = ["diff-lcs" "rspec-support"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "05j44jfqlv7j2rpxb5vqzf9hfv7w8ba46wwgxwcwd8p0wzi1hg89";
      type = "gem";
    };
    version = "3.12.3";
  };
  rspec-mocks = {
    dependencies = ["diff-lcs" "rspec-support"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1gq7gviwpck7fhp4y5ibljljvxgjklza18j62qf6zkm2icaa8lfy";
      type = "gem";
    };
    version = "3.12.6";
  };
  rspec-support = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1ky86j3ksi26ng9ybd7j0qsdf1lpr8mzrmn98yy9gzv801fvhsgr";
      type = "gem";
    };
    version = "3.12.1";
  };
  rubocop = {
    dependencies = ["json" "language_server-protocol" "parallel" "parser" "rainbow" "regexp_parser" "rexml" "rubocop-ast" "ruby-progressbar" "unicode-display_width"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "17c94wl2abqzf4fj469mdxzap1sd3410x421nl6mh2w49jsgvpki";
      type = "gem";
    };
    version = "1.55.0";
  };
  rubocop-ast = {
    dependencies = ["parser"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "188bs225kkhrb17dsf3likdahs2p1i1sqn0pr3pvlx50g6r2mnni";
      type = "gem";
    };
    version = "1.29.0";
  };
  rubocop-capybara = {
    dependencies = ["rubocop"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "01fn05a87g009ch1sh00abdmgjab87i995msap26vxq1a5smdck6";
      type = "gem";
    };
    version = "2.18.0";
  };
  rubocop-factory_bot = {
    dependencies = ["rubocop"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0kqchl8f67k2g56sq2h1sm2wb6br5gi47s877hlz94g5086f77n1";
      type = "gem";
    };
    version = "2.23.1";
  };
  rubocop-rake = {
    dependencies = ["rubocop"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1nyq07sfb3vf3ykc6j2d5yq824lzq1asb474yka36jxgi4hz5djn";
      type = "gem";
    };
    version = "0.6.0";
  };
  rubocop-rspec = {
    dependencies = ["rubocop" "rubocop-capybara" "rubocop-factory_bot"];
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "00rsflhijcr0q838fgbdmk7knm5kcjpimn6x0k9qmiw15hi96x1d";
      type = "gem";
    };
    version = "2.22.0";
  };
  ruby-progressbar = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0cwvyb7j47m7wihpfaq7rc47zwwx9k4v7iqd9s1xch5nm53rrz40";
      type = "gem";
    };
    version = "1.13.0";
  };
  simplecov = {
    dependencies = ["docile" "simplecov-html" "simplecov_json_formatter"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1hrv046jll6ad1s964gsmcq4hvkr3zzr6jc7z1mns22mvfpbc3cr";
      type = "gem";
    };
    version = "0.21.2";
  };
  simplecov-html = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0yx01bxa8pbf9ip4hagqkp5m0mqfnwnw2xk8kjraiywz4lrss6jb";
      type = "gem";
    };
    version = "0.12.3";
  };
  simplecov_json_formatter = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0a5l0733hj7sk51j81ykfmlk2vd5vaijlq9d5fn165yyx3xii52j";
      type = "gem";
    };
    version = "0.1.4";
  };
  sys-uname = {
    dependencies = ["ffi"];
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "03j9qpqip89a0vk6s0gvhxzhbvafjcj5rss7i3jwha0831aivib3";
      type = "gem";
    };
    version = "1.2.3";
  };
  thor = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0k7j2wn14h1pl4smibasw0bp66kg626drxb59z7rzflch99cd4rg";
      type = "gem";
    };
    version = "1.2.2";
  };
  unicode-display_width = {
    groups = ["default" "development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1gi82k102q7bkmfi7ggn9ciypn897ylln1jk9q67kjhr39fj043a";
      type = "gem";
    };
    version = "2.4.2";
  };
  yard = {
    groups = ["development"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "013yrnwx1zhzhn1fnc19zck22a1qgimsaglp2iwgf5bz9l8h93js";
      type = "gem";
    };
    version = "0.9.34";
  };
}
