# Plano de Continuidade de Negócios (PCN)
## SolidaryTech - Plataforma de Doações

**Versão:** 1.0  
**Data:** 26 de Setembro de 2026  
**Responsável:** Equipe de Infraestrutura

---

## 1. Visão Geral

Este documento define a estratégia de continuidade de negócios e recuperação de desastres para a plataforma SolidaryTech, garantindo que os serviços críticos possam ser restaurados em caso de falhas de infraestrutura, regionais ou de datacenter.

### 1.1 Objetivos

- Minimizar o tempo de inatividade dos serviços críticos
- Proteger dados de doações e voluntários
- Estabelecer procedimentos claros de recuperação
- Garantir conformidade com requisitos de disponibilidade

---

## 2. Definições de RTO e RPO

### 2.1 Recovery Time Objective (RTO)

**RTO = 4 horas** para dados de doações

- Tempo máximo aceitável para restaurar o sistema de doações após uma falha
- Inclui: recuperação de infraestrutura, banco de dados e aplicação
- Justificativa: Doações são críticas para a operação, mas 4 horas é aceitável para um cenário de desastre

**RTO = 8 horas** para dados de voluntários

- Sistema de voluntários é menos crítico que doações
- Pode operar em modo degradado por período mais longo

### 2.2 Recovery Point Objective (RPO)

**RPO = 15 minutos** para dados de doações

- Perda máxima de dados aceitável para doações
- Justificativa: 15 minutos de doações perdidas é aceitável em cenário de desastre
- Implementado via: RDS automated backups (7-day retention) + Velero cluster backups (daily)

**RPO = 1 hora** para dados de voluntários

- Sistema de voluntários pode tolerar maior perda de dados
- Implementado via: DynamoDB point-in-time recovery (35-day retention)

---

## 3. Sistemas Críticos

### 3.1 Prioridade 1: Sistema de Doações

- **Componentes:** donation-service, RDS PostgreSQL, SQS
- **RTO:** 4 horas
- **RPO:** 15 minutos
- **Backup:** RDS automated backups (7-day retention)
- **Recuperação:** RDS point-in-time recovery + Velero cluster restore

### 3.2 Prioridade 2: Sistema de Voluntários

- **Componentes:** volunteer-service, DynamoDB
- **RTO:** 8 horas
- **RPO:** 1 hora
- **Backup:** DynamoDB point-in-time recovery (35-day retention)
- **Recuperação:** DynamoDB restore + Velero cluster restore

### 3.3 Prioridade 3: Sistema de ONGs

- **Componentes:** ngo-service, RDS PostgreSQL
- **RTO:** 8 horas
- **RPO:** 1 hora
- **Backup:** RDS automated backups (7-day retention)
- **Recuperação:** RDS point-in-time recovery + Velero cluster restore

---

## 4. Estratégia de Backup

### 4.1 Backup de Cluster (Velero)

- **Frequência:** Diário
- **Retenção:** 30 dias
- **Armazenamento:** S3 bucket (us-east-1)
- **Conteúdo:**
  - Kubernetes manifests (deployments, services, configmaps)
  - Secrets (incluindo credenciais de banco de dados)
  - Persistent volumes (se aplicável)
  - ArgoCD Application definitions

### 4.2 Backup de Banco de Dados (AWS Native)

- **RDS PostgreSQL:**
  - Automated backups: 7-day retention
  - Point-in-time recovery: habilitado
  - Multi-AZ: desabilitado (custo)
  
- **DynamoDB:**
  - Point-in-time recovery: habilitado (35-day retention)
  - Backup sob demanda: disponível

---

## 5. Procedimentos de Recuperação

### 5.1 Cenário 1: Falha de Cluster EKS

**Sintomas:**
- Cluster EKS indisponível
- Pods não respondem
- kubectl commands falham

**Procedimento:**

1. **Verificar status do cluster:**
   ```bash
   aws eks describe-cluster --name solidarytech-production --region us-east-1
   ```

2. **Se cluster não puder ser recuperado, restaurar via Velero:**
   ```bash
   velero restore create --from-backup <backup-name> --namespace solidarytech
   velero restore get
   velero restore logs <restore-name>
   ```

3. **Verificar pods e serviços:**
   ```bash
   kubectl get pods -n solidarytech
   kubectl get svc -n solidarytech
   ```

4. **Testar endpoints de saúde:**
   ```bash
   curl http://<load-balancer-url>/health
   ```

**Tempo estimado:** 2-4 horas

### 5.2 Cenário 2: Falha de Banco de Dados RDS

**Sintomas:**
- Aplicações reportam erro de conexão com banco
- RDS instance status: unavailable

**Procedimento:**

1. **Verificar status do RDS:**
   ```bash
   aws rds describe-db-instances --db-instance-identifier solidarytech-production-donation-db
   ```

2. **Se RDS não puder ser recuperado, restaurar via point-in-time recovery:**
   ```bash
   aws rds restore-db-instance-to-point-in-time \
     --source-db-instance-identifier solidarytech-production-donation-db \
     --target-db-instance-identifier solidarytech-production-donation-db-restored \
     --restore-to-time 2026-09-26T13:00:00Z \
     --region us-east-1
   ```

3. **Atualizar DNS/endpoint se necessário:**
   - Atualizar SSM parameter com novo endpoint
   - Redeploy serviços via ArgoCD

4. **Verificar integridade dos dados:**
   ```bash
   psql -h <new-endpoint> -U <username> -d <database> -c "SELECT COUNT(*) FROM donations;"
   ```

**Tempo estimado:** 1-2 horas

### 5.3 Cenário 3: Falha Regional (us-east-1)

**Sintomas:**
- Toda região AWS us-east-1 indisponível
- Falha de múltiplos serviços

**Procedimento:**

1. **Ativar DR em região secundária (se configurado):**
   - Terraform apply em região secundária
   - Restaurar backups Velero de S3 cross-region
   - Restaurar RDS via snapshot cross-region

2. **Atualizar DNS para apontar para nova região:**
   - Atualizar Route53 records
   - Configurar health checks

3. **Verificar funcionamento dos serviços:**
   - Testar endpoints de saúde
   - Verificar integridade dos dados

**Tempo estimado:** 4-8 horas

---

## 6. Teste e Validação

### 6.1 Testes Mensais

- Verificar integridade dos backups Velero
- Testar restore de backup Velero em namespace de teste
- Verificar retenção de backups RDS e DynamoDB

### 6.2 Testes Trimestrais

- Simular falha de cluster e executar restore
- Simular falha de RDS e executar point-in-time recovery
- Documentar tempo de recuperação real vs. RTO

### 6.3 Testes Anuais

- Simular falha regional (se multi-region configurado)
- Revisar e atualizar documento PCN
- Treinar equipe em procedimentos de recuperação

---

## 7. Responsabilidades

| Papel | Responsabilidade |
|-------|------------------|
| DevOps Engineer | Manter Velero, monitorar backups, executar restores |
| Database Administrator | Monitorar RDS backups, executar point-in-time recovery |
| Site Reliability Engineer | Atualizar PCN, conduzir testes, documentar incidentes |
| Engineering Manager | Aprovar mudanças em RTO/RPO, garantir recursos |

---

## 8. Comunicação

### 8.1 Durante Incidente

1. Notificar stakeholders em 15 minutos
2. Atualizar status page (se aplicável)
3. Estimar tempo de recuperação
4. Comunicar progresso a cada 30 minutos

### 8.2 Pós-Incidente

1. Documentar root cause
2. Calcular tempo real de recuperação vs. RTO
3. Identificar melhorias
4. Atualizar PCN se necessário

---

## 9. Referências

- [Velero Documentation](https://velero.io/docs/)
- [AWS RDS Backup and Restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithBackups.html)
- [AWS DynamoDB Point-in-Time Recovery](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/PointInTimeRecovery.html)
- [AWS EKS Disaster Recovery](https://docs.aws.amazon.com/eks/latest/userguide/disaster-recovery.html)

---

## 10. Aprovação

| Papel | Nome | Data | Assinatura |
|-------|------|------|------------|
| Engineering Manager | | | |
| DevOps Lead | | | |
| SRE Lead | | | |
