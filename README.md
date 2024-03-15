
# Git pull automation on Cloudways
A composite GitHub Action designed to automate the process of initiating a Git pull request on a Cloudways application.

## Usage

### Pre-requisites
Create a workflow `.yml` file in your repository's .`github/workflows` directory. An [example workflow](#example-workflow) is available below. For more information, refer to the GitHub Help Documentation for creating a [workflow file](https://docs.github.com/en/actions/using-workflows).

#### Github Secrets
* `CLOUDWAYS_EMAIL` Cloudways primary account email
* `CLOUDWAYS_API_KEY` API Key generated on [Cloudways Platform API](https://support.cloudways.com/en/articles/5136065-how-to-use-the-cloudways-api) Section

#### Environment Variables
* `app_id` Numeric ID of the application.
* `server_id` Numeric ID of the server.
* `branch_name` Git branch name.
* `deploy_path` (optional) To set deploy_path other than public_html, define the folder name.

#### Outputs
* `is_deployed` Return status of git pull operation.

#### Example workflow
Execute SSH commands on Cloudways server after a Git pull
```yaml
name: Git pull automation
on: [push]

env:
  app_id: 8301971
  server_id: 3218642
  branch_name: main
  deploy_path: public

jobs:
  post_git_deployment_task:
    runs-on: ubuntu-latest
    name: Post Git deployment SSH task
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Pull Git Repo
        id: git-pull
        uses: elishaJ/cloudways-git-pull@v1
        continue-on-error: false
        with:
          EMAIL: ${{ secrets.CLOUDWAYS_EMAIL }}
          API_KEY: ${{ secrets.CLOUDWAYS_API_KEY }}
          APP_ID: ${{ env.app_id }}
          SERVER_ID: ${{ env.server_id }}
          BRANCH_NAME: ${{ env.branch_name }}
          DEPLOY_PATH: ${{ env.deploy_path }}

      - name: SSH Key Setup
        id: ssh-auth-setup
        if: ${{ steps.git-pull.outputs.is_deployed }} == true
        uses: elishaJ/cloudways-auth-setup@v1
        continue-on-error: false
        with:
          EMAIL: ${{ secrets.CLOUDWAYS_EMAIL }}
          API_KEY: ${{ secrets.CLOUDWAYS_API_KEY }}
          APP_ID: ${{ env.app_id }}
          SERVER_ID: ${{ env.server_id }}

      - name: SSH task
        id: ssh-task
        run: | 
          master_user="${{ steps.ssh-auth-setup.outputs.master-user }}"
          sys_user="${{ steps.ssh-auth-setup.outputs.sys-user }}"
          public_ip="${{ steps.ssh-auth-setup.outputs.server-ip }}"
          key_path="${{ steps.ssh-auth-setup.outputs.key-path }}"
          ssh -i $key_path -o StrictHostKeyChecking=no $master_user@$public_ip 'bash -s' <<EOF
          # Task to done on app hosted on the server
          cd /home/master/applications/$sys_user/public_html/;
            touch gitaction03-05.txt
          EOF
      - name: SSH Key Cleanup
        if: steps.ssh-auth-setup.outputs.task-id != ''
        uses: elishaJ/cloudways-auth-cleanup@v1
        with:
          EMAIL: ${{ secrets.CLOUDWAYS_EMAIL }}
          API_KEY: ${{ secrets.CLOUDWAYS_API_KEY }}
          TASK_ID: ${{ steps.ssh-auth-setup.outputs.task-id }}
```
