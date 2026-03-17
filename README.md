E Commerce Three Tier Application hosted on AWS

This project is a production ready cloud native application deployed on EKS AWS.I specifically used the robot-shop microservices application as it mirrors industry standards use cases in this day and age where Microservices working together which are written in different languages communicte with each other to host the application.


Application

To run the application locally:
Fork the instana robotshop source code repo from github
Run: docker compose up -d to run the application, this will bring up the robot-shop application 

Attach a video of how the application works- Please use the loom video for a small presentation to see the application running on local host.

(https://www.loom.com/share/6a9283a627ac4616a5780a99c53f7aa7)

Contanerization:

Each application has been containerized using Docker principles.I used alpine and slim based images to reduce the image significantly by around a 45% and used multi stage builds where possible to further reduce image size.

I finally wrote a docker compose file to bring all my containers together by creating a network.

Main Keypoints:   Shipping Relies on Mysql, cart relies on redis, user relies on mongodb and redis,catalogue relies on mongodb, dispatch relies on rabbitmq, payment relies on rabbitmq,  ratings relies on mysql

This is important as the services rely on the readiness of the databases to ensure the app runs effectively.Shipping relies on mysql because mysql holds the database of cities, so shipping cant run if it cant get the cities to choose which one to place the order.

Cart relies on redis for user session and saving the item in cart and it doesnt require complex queries and the carts are also temporary so they dont need storage.Redis also acts as a shared persisten-enough store which survies pod crashed in k8s.


Terraform -Bootstrapping

This module is key, essentially the backbone of ensuring systems are ready before deploying the application to EKS.

In this module I have created ECR IAM Roles which allows access to the ecr repositories and pull images using the polcies and a policy attachment.I then created all the ecr repositories required as this is where I will be pushing my docker images to.All the repositories have been ecrytpted using KMS 


Terraform - Talk about each module and why I did it this way.

