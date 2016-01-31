#!/bin/bash

cat > tmp.sh <<'BASH'
#!/bin/bash
rm -v $0
BASH

chmod +x tmp.sh
./tmp.sh
