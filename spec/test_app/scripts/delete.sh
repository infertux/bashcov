#!/usr/bin/env bash

cat > tmp.sh <<'BASH'
#!/usr/bin/env bash
rm -v $0
BASH

chmod +x tmp.sh
./tmp.sh
