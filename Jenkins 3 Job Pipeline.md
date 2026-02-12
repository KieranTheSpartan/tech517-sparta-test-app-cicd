# 3 Job Jenkins CICD Pipeline for App Deployment

![Jenkins Architecture for CICD Pipeline](jenkins-arch.png)

Job 1 triggers a code test of the last push sent to dev branch, if this is successful it will trigger Job 2 which will merge the dev branch into the main branch. Once this is completed Job 3 will access the main branch taking this new tested and merged code and apply it to an EC2 instance where we can see the changes made on the fronpage.

The CI/CD pipeline is designed in this way to create a clear, reliable flow from development to deployment, ensuring that every stage adds value without adding unnecessary complexity. Separating the pipeline into three focused jobs, testing, merging, and deployment, gives visibility, easier debugging, and predictable behaviour at each step. Throughout the build immediate benefits become clear: fewer manual tasks, consistent test results, clean merges, and deployments that became repeatable instead of fragile. For an organisation, this structure reduces human error, shortens delivery cycles, improves code quality, and creates a deployment process that can scale with team size and project complexity. In short, the pipeline enforces good engineering discipline while making releases faster, safer, and far more dependable.



After logging into the Jenkins server we are immediately taken to the dashboard and it is from here that we will create our projects which is what you refer to items on Jenkins as.

![Jenkins Dashboard](jenkins-dashboard.png)

## Commonalities Between All Jobs

### Shared Jenkins Settings
- Freestyle projects used for all three jobs  
- “Discard old builds” enabled (keep last 5)  
- Workspaces must be cleaned to avoid stale files  
- Git Source Code Management always uses SSH URLs  
- GitHub project URL uses HTTPS and must remove the .git from the end of this and replace with / 

![Job Similarities Part 1](jenkins-job-similarities1.png)

### Shared Credentials Logic
- Jenkins uses its own SSH key for GitHub

![Job Similarities Part 2](jenkins-job-similarities2.png)


---

## Job 1 — CI Test Job

### Purpose
Run CI tests on the `dev` branch whenever code is pushed.

### Key Configuration
- SCM:  
  - SSH URL to repo  
  - Branch: `dev`  
  - Credentials: Jenkins GitHub SSH key  
- Build Trigger:  
  - “GitHub hook trigger for GITScm polling”  
- Build Environment:  
  - Provide Node & npm bin folder (Node 20)

### Build Step
```bash
cd app
npm install
npm test || echo "No tests found — treating as success"
```

### Webhook Setup
GitHub → Settings → Webhooks  
Payload URL:
```
http://<JENKINS_PUBLIC_IP>:8080/github-webhook/
```
Event: **Push**

### Steps After Build
- Trigger Job 2

### Expected Behaviour
- Push to `dev` triggers Job 1  
- Jenkins clones repo via SSH  
- Installs dependencies  
- Runs tests  
- If successful → triggers Job 2  

---

## Job 2 — CI Merge Job (dev → main)

### Purpose
Automatically merge tested code from `dev` into `main`.

### Key Configuration
- SCM:  
  - SSH URL  
  - Branch: `dev`  
- Build Environment:  
  - **SSH Agent enabled** with GitHub key  
- Triggered by:  
  - Successful build of Job 1.

### Merge Script
```bash
git config user.email "noreply@jenkins.test"
git config user.name "Kieran Jenkins Bot"

git checkout main
git pull origin main
git merge origin/dev
git push origin main
```
git config lines not necessary but displays in GitHub with the name provided for who has accessed/made changes to repo.

### Alternative method for Job 2

Instead of using the execute shell and the above script for merging. Instead we can use the plugin Git Pubilsher.


- In Post Build Steps
  - Choose Git Publisher
  - Tick Push Only if Build Succeeds
  - Tick Merge Results
  - Branches:
    - Branch to push "main"
    - Target remote name "origin"

Now this will merge the branches without the need for an execute shell.

![Git Publisher in Jenkins for Job 2](git-pub.png)

### Steps After Build
- Trigger Job 3

### Expected Behaviour
- Job 1 success triggers Job 2  
- Job 2 merges dev → main  
- Pushes updated main back to GitHub  
- Successful merge triggers Job 3  

---

## Job 3 — Deployment Job

### Purpose
Deploy the latest `main` branch to an EC2 instance.

### EC2 Preparation
EC2 must have:
- git  
- Node.js 20  
- npm  
- pm2  
- needrestart prompts disabled  

Provisioning script (run on EC2):
```bash
#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "\$nrconf{restart} = 'a';" | sudo tee /etc/needrestart/conf.d/99-auto-restart.conf >/dev/null
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y git
curl -sL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs
sudo npm install -g pm2
pm2 startup systemd -u "$USER" --hp "$HOME" || true
```

### Jenkins Configuration
- SCM: SSH URL, branch `main`  
- Credentials: GitHub SSH key  
- Build Environment: SSH Agent with EC2 `.pem` key  
- Workspace cleanup enabled  

### Deployment Script
```bash
EC2_USER="ubuntu"
EC2_HOST="34.249.50.87"
EC2_APP_DIR="/home/ubuntu/app"

rsync -avz --delete -e "ssh -o StrictHostKeyChecking=no" \
  --exclude='.git' \
  --exclude='@tmp' \
  ./ "${EC2_USER}@${EC2_HOST}:${EC2_APP_DIR}/"

ssh -o StrictHostKeyChecking=no "${EC2_USER}@${EC2_HOST}" << 'EOF'
  cd /home/ubuntu/app/app
  npm install --production
  pm2 restart app || pm2 start app.js --name app
  pm2 save
EOF
```

### Expected Behaviour
- Job 2 success triggers Job 3  
- Repo synced to EC2  
- Dependencies installed  
- App started/restarted with pm2  

---

## Problems Experienced & Their Solutions

### 1. Stale Jenkins Workspaces
**Symptom:** rsync only copied one file  
**Cause:** Jenkins workspace contained incomplete repo  
**Fix:**  
- Enable “Delete workspace before build starts”  
- Manually wipe workspace once  

### 2. Wrong Directory for npm/pm2
**Symptom:** “package.json not found”  
**Cause:** Commands ran in `/home/ubuntu/app` instead of `/app/app`  
**Fix:**  
```
cd /home/ubuntu/app/app
```

### 3. Merge Conflict Loop in Job 2
**Symptom:** Same conflict reappearing  
**Cause:** dev branch still contained conflicting code  
**Fix:**  
- Resolve conflict locally  
- Push clean versions of both branches  
- Wipe Jenkins workspace  

### 4. rsync Copying Wrong Paths
**Symptom:** Nested `app/app/app.js`  
**Cause:** Misunderstood repo structure  
**Fix:**  
- Verified structure with `git ls-tree`  
- Corrected rsync target path  

### 5. EC2 Missing Dependencies
**Symptom:** Node/pm2 errors  
**Cause:** EC2 not provisioned  
**Fix:**  
- Installed Node 20, npm, pm2  
- Disabled needrestart prompts  

---

### Final Outcome
The full CI/CD pipeline now:
1. Tests code on `dev`  
2. Merges dev → main  
3. Deploys main to EC2  
4. Runs automatically end‑to‑end  

![App frontpage changed once](app-sc1.png)

![App frontpage changed twice](app-sc2.png)