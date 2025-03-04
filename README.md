## incentra contracts
- Campaign: main contract, accept zk attested rewards and user claim
- Rewards: keep track of per user per token reward amount and claimed. also tracks each user's last attested epoch. indirect rewards(eg. ALM) has additional map of contract-user-epoch
- TotalFee: epoch-fee map

Campaign inherits Rewards which inherits TotalFee