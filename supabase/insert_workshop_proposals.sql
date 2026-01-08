-- Insert workshop proposals from January 12-16, 2025
-- These are real proposals from the workshops
-- Note: Some fields are incomplete as groups didn't fill all fields correctly

-- Mesa 1 - AVG Spa and Children (AVG Spa)
INSERT INTO public.proposals (
    title,
    objectives,
    functionalities,
    discussion,
    voting_period_id,
    language
) VALUES (
    'AVG Spa and Children (AVG Spa)',
    '[
        {
            "id": "1",
            "value": "Abrir outro AVG Spa no norte do país (por exemplo: Porto)",
            "preconditions": [
                {
                    "id": "1-1",
                    "value": "Divulgação da Marinha",
                    "indicativeSteps": [{"id": "1-1-step-1", "value": "N/A"}],
                    "keyIndicators": [{"id": "1-1-indicator-1", "value": "N/A"}]
                },
                {
                    "id": "1-2",
                    "value": "Criação do navio spa and children",
                    "indicativeSteps": [{"id": "1-2-step-1", "value": "N/A"}],
                    "keyIndicators": [{"id": "1-2-indicator-1", "value": "N/A"}]
                }
            ]
        },
        {
            "id": "2",
            "value": "Abrir um AVG Spa no estrangeiro (por exemplo: São Paulo)",
            "preconditions": [
                {
                    "id": "2-1",
                    "value": "Criação de atividades didáticas",
                    "indicativeSteps": [{"id": "2-1-step-1", "value": "N/A"}],
                    "keyIndicators": [{"id": "2-1-indicator-1", "value": "N/A"}]
                },
                {
                    "id": "2-2",
                    "value": "Criar fundos para/investigação",
                    "indicativeSteps": [{"id": "2-2-step-1", "value": "N/A"}],
                    "keyIndicators": [{"id": "2-2-indicator-1", "value": "N/A"}]
                }
            ]
        }
    ]'::jsonb,
    'Gestão financeira
Recurso humanos (recrutamento)
Plataforma de reservas (clientes)
Concurso p/manutenções
Jogos interativos com a história da marinha',
    'Envolvimento das faculdades/universidades
Diversificar público-alvo',
    'january-2025-exceptional',
    'pt'
);

-- Mesa 2 - Proibição de ter animais em cativeiro
INSERT INTO public.proposals (
    title,
    objectives,
    functionalities,
    discussion,
    voting_period_id,
    language
) VALUES (
    'Proibição de ter animais em cativeiro (cenário selecionado), Melhores espaço zoológico nacional, Melhor centro de investigação sobre o mar',
    '[
        {
            "id": "1",
            "value": "Não ter animais na exposição do AVG",
            "preconditions": [
                {
                    "id": "1-1",
                    "value": "Forma de libertar os animais. Transporte. Para encontrar uma solução ética",
                    "indicativeSteps": [{"id": "1-1-step-1", "value": "Obter transportes"}],
                    "keyIndicators": [{"id": "1-1-indicator-1", "value": "Garantir a liberdade no espaço humano. Limite: a meio do ano, libertar 40%"}]
                },
                {
                    "id": "1-2",
                    "value": "Reintegrar a equipa que era responsável pela sua manutenção",
                    "indicativeSteps": [{"id": "1-2-step-1", "value": "Perceber vontades"}],
                    "keyIndicators": [{"id": "1-2-indicator-1", "value": "Público-alvo: a equipa. Meta: reintegrar 100% da equipa no espaço de 2 anos. Limite: Reintegrar 80% no mesmo tempo"}]
                }
            ]
        },
        {
            "id": "2",
            "value": "Ter um Aquário completamente digital",
            "preconditions": [
                {
                    "id": "2-1",
                    "value": "Remodelação total do Aquário",
                    "indicativeSteps": [
                        {"id": "2-1-step-1", "value": "Procurar financiamento"},
                        {"id": "2-1-step-2", "value": "Projeto arquitetónico"}
                    ],
                    "keyIndicators": [{"id": "2-1-indicator-1", "value": "Público-alvo: visitantes. Meta 1: terminar o projeto no 1º ano. Meta 2: terminar a obra em 3 anos. Limite 1: Terminar o projeto em ano e meio. Limite 2: Terminar a obra em 4 anos"}]
                },
                {
                    "id": "2-2",
                    "value": "Desenvolvimento das capacidades tecnológicas do Aquário",
                    "indicativeSteps": [
                        {"id": "2-2-step-1", "value": "Formar equiap tecnologica"},
                        {"id": "2-2-step-2", "value": "Parcerias com empresas e instituições"}
                    ],
                    "keyIndicators": [{"id": "2-2-indicator-1", "value": "Público-alvo: visitantes. Meta: Nos 2 anos manter nº de visitantes antes do fecho. Limite: Nos 2 anos obter 75% do nº de visitantes"}]
                }
            ]
        }
    ]'::jsonb,
    'Guia de ética ambiental e animal
Sistema de voto sobre a exposição
Gerir licenças de libertação
Gerir licenças de software
Avaliação de aptidões dos funcionários
Sugestões de funções p/funcionários
Conselho de ecossistema
Medir imposto de doações
Gestão de stock',
    'N/A',
    'january-2025-exceptional',
    'pt'
);

-- Mesa 3 - Algoteca
INSERT INTO public.proposals (
    title,
    objectives,
    functionalities,
    discussion,
    voting_period_id,
    language
) VALUES (
    'Algoteca (backup de algas, resgate animal com multiplas de intercambio)',
    '[
        {
            "id": "1",
            "value": "Refúgio de organismos aquáticos",
            "preconditions": [
                {
                    "id": "1-1",
                    "value": "Coleta",
                    "indicativeSteps": [
                        {"id": "1-1-step-1", "value": "deteção das espécies portugueses"},
                        {"id": "1-1-step-2", "value": "saídas de campo (+)"}
                    ],
                    "keyIndicators": [{"id": "1-1-indicator-1", "value": "Recursos materiais e humanos"}]
                },
                {
                    "id": "1-2",
                    "value": "Backup",
                    "indicativeSteps": [
                        {"id": "1-2-step-1", "value": "Participação de resgate"},
                        {"id": "1-2-step-2", "value": "Adaptação dos atuais no Aquário"}
                    ],
                    "keyIndicators": [{"id": "1-2-indicator-1", "value": "Referência nacional"}]
                }
            ]
        },
        {
            "id": "2",
            "value": "Ponto de resgate",
            "preconditions": [
                {
                    "id": "2-1",
                    "value": "Referencia nacional",
                    "indicativeSteps": [
                        {"id": "2-1-step-1", "value": "Projetos de investigação (+)"},
                        {"id": "2-1-step-2", "value": "Reprodução de espécies"}
                    ],
                    "keyIndicators": [{"id": "2-1-indicator-1", "value": "Pesquisa: Número de espécies: 1 a 3 espécies p/ano. Publico-alvo: organizações e governo"}]
                },
                {
                    "id": "2-2",
                    "value": "Adaptação do edificio",
                    "indicativeSteps": [{"id": "2-2-step-1", "value": "Financiamento"}],
                    "keyIndicators": [{"id": "2-2-indicator-1", "value": "N/A"}]
                }
            ]
        }
    ]'::jsonb,
    'AVG 2025
1. Unidade operacional (embarcações, recursos humanos, veículo)
   Marinha Portuguesa (coleta)
2. Divulgação (dinamizar escolas distintas, campanhas, horários de alimentação, redes sociais, serviço educativo)
   Escolas, Faculdades, Associações
   Escolas, Redes sociais
3. Investigação (Algoteca. Projetos)
   IPMA
   Faculdades
4. Recolha, Resgate, Recuperação Animal
   ICNF
   IPMA
   GNR, Associações independentes
5. Exposição (novas espécies, conservação costa portuguesa)',
    'N/A',
    'january-2025-exceptional',
    'pt'
);
