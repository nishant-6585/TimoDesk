-- seed/seed_kb.sql
-- Sample knowledge base chunks for testing
-- Embeddings will be populated by the voice pipeline later

insert into kb_chunk (topic, content, is_faq, source) values
  (
    'company',
    'xboom is an Indian company building robots, drones, and underwater ROVs — the only company operating across all three domains: land, air, and water. We specialize in automation solutions for agriculture, inspection, and service industries.',
    true,
    'manual'
  ),
  (
    'products',
    'xboom builds agricultural drones for precision farming, inspection ROVs for confined spaces like pipelines and tanks, and service robots for reception and hospitality. Our Mikee robot is designed to greet visitors, answer questions, and perform security patrols.',
    true,
    'manual'
  ),
  (
    'mikee',
    'I am Mikee, the reception robot at xboom. I can greet visitors by name (if enrolled), answer questions about our products and services, capture visitor information, and guide you to the right team member. I am available to assist during office hours.',
    true,
    'manual'
  ),
  (
    'contact',
    'To reach the xboom team, you can ask me to notify your host and I will send them a message right away. For general enquiries or to learn more, visit xboom.in or contact our office during business hours.',
    true,
    'manual'
  ),
  (
    'office',
    'The xboom office is open Monday to Friday, 9 AM to 6 PM. Our team works across robotics, drone technology, and underwater systems. We have expertise in precision agriculture, industrial inspection, and autonomous systems. Welcome to xboom!',
    false,
    'manual'
  );

comment on table kb_chunk is 'Knowledge base loaded via seed_kb.sql. Embeddings are NULL until voice pipeline populates them.';
